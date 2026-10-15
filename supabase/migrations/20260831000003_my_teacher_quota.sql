-- =============================================================================
-- B4 (Sprint 4) — RPC : le prof consulte son propre quota individuel
--
-- CONTEXTE : L'admin attribue à chaque prof un quota de crédits sur le pool
-- de l'école (via table teacher_quotas). Aujourd'hui le prof ne voit pas
-- combien de crédits l'admin lui a donnés — il tape à l'aveugle.
--
-- Cette RPC lui permet de savoir :
--   - limit_total : combien l'admin lui a attribué
--   - used        : combien il a déjà consommé
--   - remaining   : ce qui lui reste
--   - has_limit   : true si un quota est actif, false sinon
-- =============================================================================

create or replace function public.get_my_teacher_quota()
returns table (
  out_establishment_id uuid,
  out_establishment_name text,
  out_limit_total int,
  out_used int,
  out_remaining int,
  out_has_limit boolean
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then return; end if;

  return query
  select
    tq.establishment_id,
    e.name,
    tq.limit_total,
    tq.used,
    greatest(0, tq.limit_total - tq.used) as remaining,
    (tq.limit_total > 0) as has_limit
  from public.teacher_quotas tq
  join public.establishments e on e.id = tq.establishment_id
  join public.establishment_members m
    on m.establishment_id = tq.establishment_id
   and m.user_id = _v_user_id
   and m.is_active = true
  where tq.user_id = _v_user_id;
end;
$$;

grant execute on function public.get_my_teacher_quota() to authenticated;
