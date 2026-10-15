-- =============================================================================
-- Correction Michel (Sprint 4 renforcé) — Isolation stricte des crédits
--                                          par école active.
--
-- RÈGLE ATTENDUE (retour Michel) :
-- "Quand le prof change d'établissement, il doit utiliser UNIQUEMENT les
--  crédits attribués par l'admin de l'école sur laquelle il est actif.
--  Il ne doit jamais pouvoir utiliser les crédits d'une école pendant
--  qu'il est actif sur un autre compte secondaire d'une autre école."
--
-- LOGIQUE FIX :
--   - Si p_establishment_id fourni (prof actif dans une école) :
--       → Skip totalement le wallet perso
--       → Réservation UNIQUEMENT depuis le pool de cette école
--       → Check quota individuel de la table teacher_quotas
--   - Si p_establishment_id null (mode solo — prof sans école) :
--       → Wallet perso comme avant
-- =============================================================================

create or replace function public.reserve_credit(
  p_copy_id uuid,
  p_establishment_id uuid default null
)
returns table (
  out_ok boolean,
  out_lot_id uuid,
  out_remaining_after int,
  out_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_lot_id  uuid;
  _v_rem     int;
  _v_owner_estab uuid;
  _v_pool_lot uuid;
  _v_quota_limit int;
  _v_quota_used int;
begin
  if _v_user_id is null then
    out_ok := false; out_reason := 'NOT_AUTHENTICATED';
    return next; return;
  end if;

  -- Détermine l'école active (soit passée explicitement, soit auto)
  if p_establishment_id is not null then
    -- Vérifie que le prof est bien membre actif de cette école
    if not exists (
      select 1 from public.establishment_members
      where establishment_id = p_establishment_id
        and user_id = _v_user_id
        and is_active = true
    ) then
      out_ok := false; out_reason := 'NOT_MEMBER_OF_ESTABLISHMENT';
      return next; return;
    end if;
    _v_owner_estab := p_establishment_id;
  else
    -- Fallback : cherche s'il est membre d'AU MOINS UNE école (mono-école)
    select establishment_id into _v_owner_estab
    from public.establishment_members
    where user_id = _v_user_id and is_active = true
    limit 1;
  end if;

  -- ═══════════════════════════════════════════════════════════════════════
  -- BRANCHE 1 : Prof dans une école active → ISOLATION STRICTE
  -- ═══════════════════════════════════════════════════════════════════════
  -- On skippe totalement le wallet perso et on prélève UNIQUEMENT sur le
  -- pool de l'école active. Le prof ne peut pas cross-utiliser ses crédits.
  if _v_owner_estab is not null then
    -- 1a. Vérifie quota individuel attribué par l'admin
    select limit_total, used into _v_quota_limit, _v_quota_used
    from public.teacher_quotas
    where establishment_id = _v_owner_estab and user_id = _v_user_id;

    -- Si aucun quota n'est défini (limit_total = 0 par défaut), le prof
    -- n'a rien reçu de l'admin → refus explicite.
    if _v_quota_limit is null or _v_quota_limit = 0 then
      out_ok := false; out_reason := 'QUOTA_NOT_SET';
      return next; return;
    end if;

    -- Si quota atteint → refus
    if _v_quota_used >= _v_quota_limit then
      out_ok := false; out_reason := 'QUOTA_EXCEEDED';
      return next; return;
    end if;

    -- 1b. Prélève sur le pool de CETTE école (FIFO)
    select id, credits_remaining
      into _v_pool_lot, _v_rem
    from public.credit_lots
    where owner_kind = 'establishment'
      and owner_establishment_id = _v_owner_estab
      and status = 'active'
      and credits_remaining > 0
      and expires_at > now()
    order by expires_at asc
    limit 1
    for update;

    if _v_pool_lot is null then
      out_ok := false; out_reason := 'NO_CREDITS_IN_POOL';
      return next; return;
    end if;

    update public.credit_lots
      set credits_remaining = credits_remaining - 1,
          status = case when credits_remaining - 1 = 0 then 'exhausted' else status end
      where id = _v_pool_lot;
    update public.teacher_quotas
      set used = used + 1, updated_at = now()
      where establishment_id = _v_owner_estab and user_id = _v_user_id;
    insert into public.credit_transactions
      (lot_id, user_id, establishment_id, txn_type, delta, reason, ref_copy_id)
    values (_v_pool_lot, _v_user_id, _v_owner_estab, 'reserve', -1,
            'copy_reserve_pool', p_copy_id);
    out_ok := true;
    out_lot_id := _v_pool_lot;
    out_remaining_after := _v_rem - 1;
    out_reason := 'OK_POOL';
    return next; return;
  end if;

  -- ═══════════════════════════════════════════════════════════════════════
  -- BRANCHE 2 : Prof SOLO (aucune école) → wallet perso
  -- ═══════════════════════════════════════════════════════════════════════
  select id, credits_remaining
    into _v_lot_id, _v_rem
  from public.credit_lots
  where owner_kind = 'user'
    and owner_user_id = _v_user_id
    and status = 'active'
    and credits_remaining > 0
    and expires_at > now()
  order by expires_at asc
  limit 1
  for update;

  if _v_lot_id is null then
    out_ok := false; out_reason := 'NO_CREDITS';
    return next; return;
  end if;

  update public.credit_lots
    set credits_remaining = credits_remaining - 1,
        status = case when credits_remaining - 1 = 0 then 'exhausted' else status end
    where id = _v_lot_id;
  insert into public.credit_transactions
    (lot_id, user_id, txn_type, delta, reason, ref_copy_id)
  values (_v_lot_id, _v_user_id, 'reserve', -1, 'copy_reserve', p_copy_id);
  out_ok := true;
  out_lot_id := _v_lot_id;
  out_remaining_after := _v_rem - 1;
  out_reason := 'OK_PERSONAL';
  return next; return;
end;
$$;

grant execute on function public.reserve_credit(uuid, uuid) to authenticated;
grant execute on function public.reserve_credit(uuid) to authenticated;
