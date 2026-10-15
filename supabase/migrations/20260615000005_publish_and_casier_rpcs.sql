-- =============================================================================
-- RPCs SECURITY DEFINER pour la publication des copies + lecture casier admin
-- =============================================================================
-- Bug observé : prof clique "Envoyer X notes au casier", snackbar de succès,
-- mais l'admin ne voit jamais ces notes dans son casier. Cause :
--   • UPDATE student_copies bloqué silencieusement par RLS côté prof
--     (published_at reste NULL en DB malgré ce que pense le client)
--   • SELECT student_copies bloqué côté admin par RLS récursive
--
-- Solution : tout passer par RPCs SECURITY DEFINER qui bypassent les RLS.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Publication des copies graded d'un examen
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.publish_exam_copies(p_exam_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_count int := 0;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;

  -- Vérifie que l'user est propriétaire de cet examen
  if not exists (
    select 1 from public.exams
    where id = p_exam_id and owner_id = _v_user_id
  ) then
    raise exception 'Vous n''êtes pas propriétaire de cet examen.';
  end if;

  -- Marque toutes les copies graded non publiées comme publiées
  update public.student_copies
  set published_at = now()
  where exam_id = p_exam_id
    and status = 'graded'
    and published_at is null;

  get diagnostics _v_count = row_count;
  return _v_count;
end;
$$;

grant execute on function public.publish_exam_copies(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Dépublication (si le prof veut retirer ses notes du casier)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.unpublish_exam_copies(p_exam_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_count int := 0;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;
  if not exists (
    select 1 from public.exams
    where id = p_exam_id and owner_id = _v_user_id
  ) then
    raise exception 'Vous n''êtes pas propriétaire de cet examen.';
  end if;

  update public.student_copies
  set published_at = null
  where exam_id = p_exam_id and published_at is not null;

  get diagnostics _v_count = row_count;
  return _v_count;
end;
$$;

grant execute on function public.unpublish_exam_copies(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lecture du casier admin : toutes les notes publiées de l'école
-- ─────────────────────────────────────────────────────────────────────────────
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
    and e.owner_id in (
      select m.user_id
      from public.establishment_members m
      where m.establishment_id = _v_admin_estab
    )
  order by c.published_at desc;
end;
$$;

grant execute on function public.get_school_casier_notes() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Activité récente des profs (pour alertes admin "X notes publiées")
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_recent_publications(p_hours int default 24)
returns table (
  out_teacher_user_id uuid,
  out_teacher_display_name text,
  out_count int,
  out_last_published_at timestamptz
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
    e.owner_id,
    p.display_name,
    count(*)::int,
    max(c.published_at)
  from public.student_copies c
  join public.exams e on e.id = c.exam_id
  left join public.profiles p on p.id = e.owner_id
  where c.published_at is not null
    and c.published_at > (now() - (p_hours || ' hours')::interval)
    and e.owner_id in (
      select m.user_id
      from public.establishment_members m
      where m.establishment_id = _v_admin_estab
    )
  group by e.owner_id, p.display_name
  order by max(c.published_at) desc;
end;
$$;

grant execute on function public.get_recent_publications(int) to authenticated;
