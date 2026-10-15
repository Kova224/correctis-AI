-- =============================================================================
-- Isolation stricte du casier par école (retour Michel).
--
-- CONTEXTE :
--   Avant : les RPCs casier admin utilisaient `e.owner_id IN (members of X)`
--   Ce qui incluait toutes les copies d'un prof, même celles d'un examen
--   fait pour une AUTRE école ou en mode solo.
--
--   Michel remarque : "les copies corrigées par Michel dans son école
--   apparaissent dans mon école quand il rejoint mon école".
--
-- FIX :
--   TOUTES les RPCs casier admin filtrent par `e.establishment_id = X`
--   STRICTEMENT. Une copie ne peut apparaître dans le casier d'une école
--   QUE si l'examen est explicitement rattaché à cette école.
--
--   Corollaire : les copies faites en mode "Solo" (establishment_id = null)
--   n'apparaissent dans AUCUN casier école. Elles restent perso.
-- =============================================================================

-- 1. get_school_casier_notes — filtre STRICT sur e.establishment_id
create or replace function public.get_school_casier_notes()
returns table (
  out_copy_id uuid,
  out_student_name text,
  out_student_ref text,
  out_exam_id uuid,
  out_exam_title text,
  out_exam_type text,
  out_class_name text,
  out_exam_total_points numeric,
  out_teacher_user_id uuid,
  out_teacher_display_name text,
  out_teacher_email text,
  out_copy_created_at timestamptz,
  out_copy_published_at timestamptz,
  out_total_score numeric
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_admin_estab uuid;
begin
  if _v_user_id is null then return; end if;

  select establishment_id into _v_admin_estab
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;

  if _v_admin_estab is null then return; end if;

  return query
  select
    c.id,
    c.student_name,
    c.student_ref,
    e.id,
    e.title,
    e.exam_type,
    e.class_name,
    e.total_points,
    e.owner_id,
    p.display_name,
    p.email,
    c.created_at,
    c.published_at,
    coalesce((
      select sum(qg.score) from public.question_grades qg
      where qg.copy_id = c.id
    ), 0)::numeric
  from public.student_copies c
  join public.exams e on e.id = c.exam_id
  left join public.profiles p on p.id = e.owner_id
  where c.status = 'graded'
    and c.published_at is not null
    -- ISOLATION STRICTE : uniquement les examens de cette école
    and e.establishment_id = _v_admin_estab
  order by c.published_at desc;
end;
$$;

grant execute on function public.get_school_casier_notes() to authenticated;

-- 2. get_casier_by_teacher — filtre STRICT sur e.establishment_id
create or replace function public.get_casier_by_teacher()
returns table (
  out_teacher_user_id uuid,
  out_teacher_name text,
  out_teacher_email text,
  out_notes_count int,
  out_classes_count int,
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
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  return query
  select
    e.owner_id,
    coalesce(p.display_name, p.email, 'Enseignant'),
    p.email,
    count(c.id)::int,
    count(distinct e.class_name)::int,
    max(c.published_at)
  from public.exams e
  join public.student_copies c on c.exam_id = e.id
  left join public.profiles p on p.id = e.owner_id
  where c.published_at is not null
    and c.status = 'graded'
    -- ISOLATION STRICTE : uniquement les examens rattachés à cette école
    and e.establishment_id = _v_estab_id
  group by e.owner_id, p.display_name, p.email
  order by max(c.published_at) desc;
end;
$$;

grant execute on function public.get_casier_by_teacher() to authenticated;

-- 3. get_teacher_classes — filtre STRICT (drop d'abord car retour changé)
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
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

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
    -- ISOLATION STRICTE : uniquement examens de cette école
    and e.establishment_id = _v_estab_id
  group by e.class_name
  order by max(c.published_at) desc;
end;
$$;

grant execute on function public.get_teacher_classes(uuid) to authenticated;

-- 4. get_class_notes — filtre STRICT
create or replace function public.get_class_notes(
  p_teacher_user_id uuid,
  p_class_name text,
  p_control_type text default null
)
returns table (
  out_copy_id uuid,
  out_student_name text,
  out_student_ref text,
  out_exam_id uuid,
  out_exam_title text,
  out_exam_type text,
  out_control_type text,
  out_exam_total_points numeric,
  out_copy_published_at timestamptz,
  out_total_score numeric
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  return query
  select
    c.id,
    c.student_name,
    c.student_ref,
    e.id,
    e.title,
    e.exam_type,
    coalesce(e.control_type, 'general'),
    e.total_points,
    c.published_at,
    coalesce((select sum(qg.score) from public.question_grades qg
              where qg.copy_id = c.id), 0)::numeric
  from public.student_copies c
  join public.exams e on e.id = c.exam_id
  where c.published_at is not null
    and c.status = 'graded'
    and e.owner_id = p_teacher_user_id
    and coalesce(e.class_name, 'Sans classe') = p_class_name
    and (p_control_type is null
         or coalesce(e.control_type, 'general') = p_control_type)
    -- ISOLATION STRICTE
    and e.establishment_id = _v_estab_id
  order by c.published_at desc;
end;
$$;

grant execute on function public.get_class_notes(uuid, text, text) to authenticated;

-- 5. get_student_releve — filtre STRICT
create or replace function public.get_student_releve(
  p_student_name text,
  p_student_ref text default null,
  p_control_type text default null
)
returns table (
  out_copy_id uuid,
  out_exam_title text,
  out_exam_type text,
  out_control_type text,
  out_class_name text,
  out_teacher_name text,
  out_exam_total_points numeric,
  out_total_score numeric,
  out_published_at timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  return query
  select
    c.id,
    e.title,
    e.exam_type,
    coalesce(e.control_type, 'general'),
    e.class_name,
    coalesce(p.display_name, p.email, 'Enseignant'),
    e.total_points,
    coalesce((select sum(qg.score) from public.question_grades qg
              where qg.copy_id = c.id), 0)::numeric,
    c.published_at
  from public.student_copies c
  join public.exams e on e.id = c.exam_id
  left join public.profiles p on p.id = e.owner_id
  where c.published_at is not null
    and c.status = 'graded'
    and lower(c.student_name) = lower(p_student_name)
    and (p_student_ref is null
         or lower(coalesce(c.student_ref, '')) = lower(p_student_ref))
    and (p_control_type is null
         or coalesce(e.control_type, 'general') = p_control_type)
    -- ISOLATION STRICTE
    and e.establishment_id = _v_estab_id
  order by c.published_at desc;
end;
$$;

grant execute on function public.get_student_releve(text, text, text) to authenticated;
