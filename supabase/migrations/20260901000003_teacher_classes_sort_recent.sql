-- =============================================================================
-- Correction Michel — Trier les classes par date de dernière note publiée
-- (du plus récent au plus ancien) dans le casier admin.
--
-- CONTEXTE : "on doit avoir une fonctionnalité qui permet de classer les
-- notes des classes envoyé par monsieur Michael d'être classes par ordre
-- du plus récent au plus ancien"
--
-- FIX :
--   - Ajoute out_last_published_at à get_teacher_classes
--   - Tri par max(published_at) DESC par défaut (plus récent en haut)
--   - Le client peut afficher un toggle UI pour inverser si voulu
-- =============================================================================

-- Postgres refuse CREATE OR REPLACE quand le type de retour change (on ajoute
-- out_last_published_at). Il faut DROP puis recréer.
drop function if exists public.get_teacher_classes(uuid);

create function public.get_teacher_classes(p_teacher_user_id uuid)
returns table (
  out_class_name text,
  out_notes_count int,
  out_control_types text[],
  out_last_published_at timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
  _v_teacher_is_active boolean;
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  select is_active into _v_teacher_is_active
  from public.establishment_members
  where establishment_id = _v_estab_id and user_id = p_teacher_user_id
  limit 1;

  return query
  select
    coalesce(e.class_name, 'Sans classe'),
    count(c.id)::int,
    array_agg(distinct coalesce(e.control_type, 'general')),
    max(c.published_at)
  from public.exams e
  join public.student_copies c on c.exam_id = e.id
  where c.published_at is not null
    and c.status = 'graded'
    and e.owner_id = p_teacher_user_id
    and (e.establishment_id = _v_estab_id
         or coalesce(_v_teacher_is_active, false) = true
         or (c.locked_at is not null and c.locked_at < now()))
  group by e.class_name
  order by max(c.published_at) desc; -- plus récent en haut
end;
$$;

grant execute on function public.get_teacher_classes(uuid) to authenticated;
