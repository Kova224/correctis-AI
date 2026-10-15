-- =============================================================================
-- B3 (Sprint 4) — Isolation multi-écoles pour la réservation de crédits
--
-- CONTEXTE (retour Michel) :
-- "rendez fonctionnelle la partie qui permet à un prof appartenant à
--  plusieurs écoles de basculer d'une école à une autre... il ne doit
--  jamais pouvoir utiliser les crédits d'une école pour corriger les
--  copies d'une autre école."
--
-- CAUSE :
--   La RPC `reserve_credit(p_copy_id)` picke la 1re école active du prof
--   via `limit 1` — c'est aléatoire quand le prof est multi-école, il
--   peut consommer les crédits de l'école A pour corriger une copie
--   liée à l'école B.
--
-- FIX :
--   - Nouveau paramètre optionnel `p_establishment_id` qui force l'école
--     depuis laquelle prélever les crédits.
--   - Le client Flutter (CreditsService/ExamService) passe l'école active
--     du prof (persistée dans SharedPreferences).
--   - Compat ascendante : si null, comportement historique (auto-pick).
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

  -- 1. Tente d'abord le wallet personnel (FIFO)
  --    C'est indépendant de l'école : les crédits perso sont utilisables partout.
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

  if _v_lot_id is not null then
    update public.credit_lots
      set credits_remaining = credits_remaining - 1,
          status = case when credits_remaining - 1 = 0 then 'exhausted' else status end
      where id = _v_lot_id;
    insert into public.credit_transactions
      (lot_id, user_id, txn_type, delta, reason, ref_copy_id)
    values (_v_lot_id, _v_user_id, 'reserve', -1, 'copy_reserve', p_copy_id);
    out_ok := true; out_lot_id := _v_lot_id; out_remaining_after := _v_rem - 1;
    out_reason := 'OK_PERSONAL';
    return next; return;
  end if;

  -- 2. Pool établissement — isolation stricte par école
  --    Si l'école est fournie explicitement (multi-école), on l'utilise.
  --    Sinon, fallback sur la 1re école active du prof (mono-école).
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
    select establishment_id into _v_owner_estab
    from public.establishment_members
    where user_id = _v_user_id and is_active = true
    limit 1;
  end if;

  if _v_owner_estab is not null then
    -- Vérifie quota individuel pour cette école
    select limit_total, used into _v_quota_limit, _v_quota_used
    from public.teacher_quotas
    where establishment_id = _v_owner_estab and user_id = _v_user_id;

    if _v_quota_limit is not null and _v_quota_limit > 0
       and _v_quota_used >= _v_quota_limit then
      out_ok := false; out_reason := 'QUOTA_EXCEEDED';
      return next; return;
    end if;

    -- Prélève sur le pool de CETTE école (FIFO)
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

    if _v_pool_lot is not null then
      update public.credit_lots
        set credits_remaining = credits_remaining - 1,
            status = case when credits_remaining - 1 = 0 then 'exhausted' else status end
        where id = _v_pool_lot;
      update public.teacher_quotas
        set used = used + 1, updated_at = now()
        where establishment_id = _v_owner_estab and user_id = _v_user_id;
      insert into public.credit_transactions
        (lot_id, user_id, establishment_id, txn_type, delta, reason, ref_copy_id)
      values (_v_pool_lot, _v_user_id, _v_owner_estab, 'reserve', -1, 'copy_reserve_pool', p_copy_id);
      out_ok := true; out_lot_id := _v_pool_lot; out_remaining_after := _v_rem - 1;
      out_reason := 'OK_POOL';
      return next; return;
    end if;
  end if;

  -- 3. Rien de dispo → pas de crédit
  out_ok := false; out_reason := 'NO_CREDITS';
  return next; return;
end;
$$;

grant execute on function public.reserve_credit(uuid, uuid) to authenticated;
-- Conserve aussi la signature à 1 param pour compat ascendante
grant execute on function public.reserve_credit(uuid) to authenticated;
