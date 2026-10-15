-- =============================================================================
-- Michel : « les crédits chez admin ne décrémentent pas quand j'attribue ».
--
-- Semantique adoptée : à chaque attribution de N crédits à un prof, ces N
-- crédits sont considérés « engagés ». Le pool physique (credit_lots) ne
-- bouge qu'à la consommation, mais on affiche à l'admin un « pool dispo »
-- = pool physique - crédits engagés (somme des remaining des quotas profs).
--
-- Change 1 : get_org_credit_wallet renvoie aussi engaged + available.
-- Change 2 : nouvelle RPC attribute_credits_to_teacher(user, amount) —
--            ADDITIVE (contrairement à update_teacher_quota qui remplace),
--            valide que le pool dispo est suffisant.
-- =============================================================================

drop function if exists public.get_org_credit_wallet();

create function public.get_org_credit_wallet()
returns table (
  out_total_credits int,       -- crédits physiques restants dans les lots
  out_active_lots_count int,
  out_next_expiration timestamptz,
  out_active_pack_name text,
  out_active_pack_total int,
  out_engaged_credits int,     -- déjà alloués aux quotas profs (non consommés)
  out_available_credits int    -- pool - engaged (dispo pour attribution)
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
  _v_physical int;
  _v_engaged int;
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  select coalesce(sum(credits_remaining), 0)::int into _v_physical
  from public.credit_lots
  where owner_kind = 'establishment'
    and owner_establishment_id = _v_estab_id
    and status = 'active';

  select coalesce(sum(greatest(0, limit_total - used)), 0)::int into _v_engaged
  from public.teacher_quotas
  where establishment_id = _v_estab_id;

  return query
  with active_lots as (
    select l.id, l.credits_remaining, l.credits_total, l.expires_at, l.pack_code
    from public.credit_lots l
    where l.owner_kind = 'establishment'
      and l.owner_establishment_id = _v_estab_id
      and l.status = 'active'
      and l.credits_remaining > 0
  )
  select
    _v_physical,
    count(*)::int,
    min(expires_at),
    (select coalesce(p.name, al.pack_code)
       from active_lots al
       left join public.credit_packs p on p.code = al.pack_code
       order by al.expires_at asc
       limit 1),
    (select credits_total from active_lots
       order by expires_at asc limit 1),
    _v_engaged,
    greatest(0, _v_physical - _v_engaged)::int
  from active_lots;
end;
$$;
grant execute on function public.get_org_credit_wallet() to authenticated;

-- Additive : ajoute p_amount au quota existant du prof (au lieu de remplacer)
create or replace function public.attribute_credits_to_teacher(
  p_user_id uuid,
  p_amount int
)
returns table (
  out_new_limit_total int,
  out_engaged int,
  out_available int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_admin_id uuid := auth.uid();
  _v_estab_id uuid;
  _v_physical int;
  _v_engaged int;
  _v_new_limit int;
begin
  if _v_admin_id is null then raise exception 'Non authentifié.'; end if;
  if p_amount <= 0 then raise exception 'Montant doit être positif.'; end if;

  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_admin_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then raise exception 'Réservé à l''administrateur.'; end if;

  if not exists (
    select 1 from public.establishment_members
     where user_id = p_user_id
       and establishment_id = _v_estab_id
       and is_active = true
  ) then
    raise exception 'Ce prof n''est pas membre de votre école.';
  end if;

  select coalesce(sum(credits_remaining), 0)::int into _v_physical
  from public.credit_lots
  where owner_kind = 'establishment'
    and owner_establishment_id = _v_estab_id
    and status = 'active';

  select coalesce(sum(greatest(0, limit_total - used)), 0)::int into _v_engaged
  from public.teacher_quotas
  where establishment_id = _v_estab_id;

  if p_amount > greatest(0, _v_physical - _v_engaged) then
    raise exception 'Pool école insuffisant : % dispos, % demandés.',
      greatest(0, _v_physical - _v_engaged), p_amount;
  end if;

  insert into public.teacher_quotas (establishment_id, user_id, limit_total, used)
  values (_v_estab_id, p_user_id, p_amount, 0)
  on conflict (establishment_id, user_id)
  do update set
    limit_total = public.teacher_quotas.limit_total + excluded.limit_total,
    updated_at = now()
  returning limit_total into _v_new_limit;

  select coalesce(sum(greatest(0, limit_total - used)), 0)::int into _v_engaged
  from public.teacher_quotas
  where establishment_id = _v_estab_id;

  out_new_limit_total := _v_new_limit;
  out_engaged := _v_engaged;
  out_available := greatest(0, _v_physical - _v_engaged);
  return next;
end;
$$;
grant execute on function public.attribute_credits_to_teacher(uuid, int) to authenticated;
