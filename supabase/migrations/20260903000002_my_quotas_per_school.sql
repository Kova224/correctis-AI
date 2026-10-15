-- =============================================================================
-- Michel (spec §6) : dans "Mes examens", chaque école a son solde de crédits
-- affiché dans l'en-tête de sa section. Nouvelle RPC qui retourne le quota
-- (limite / utilisé / restant) du prof courant dans CHAQUE école où il est
-- rattaché — pas seulement l'école active.
-- =============================================================================

drop function if exists public.get_my_teacher_quotas();

create function public.get_my_teacher_quotas()
returns table (
  out_establishment_id uuid,
  out_establishment_name text,
  out_limit_total int,
  out_used int,
  out_remaining int,
  out_has_limit boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.establishment_id,
    e.name,
    coalesce(q.limit_total, 0)::int,
    coalesce(q.used, 0)::int,
    greatest(0, coalesce(q.limit_total, 0) - coalesce(q.used, 0))::int,
    (coalesce(q.limit_total, 0) > 0) as has_limit
  from public.establishment_members m
  join public.establishments e on e.id = m.establishment_id
  left join public.teacher_quotas q
    on q.establishment_id = m.establishment_id
   and q.user_id = m.user_id
  where m.user_id = auth.uid()
    and m.is_active = true
    and m.role = 'teacher'
  order by e.name asc;
$$;

grant execute on function public.get_my_teacher_quotas() to authenticated;
