-- =============================================================================
-- Michel : deux bugs.
--
-- 1) « quand je suspends un prof et le réinvite, il apparaît 2 fois »
--    Cause racine : get_my_establishment_members() retournait les membres
--    de TOUTES les écoles où le user courant est membre, pas seulement
--    l'école qu'il administre. Un admin qui est aussi (ou a été) teacher
--    ailleurs voit les 2 listes fusionnées → dashboard duplique les chips.
--    FIX : filtrer STRICT sur l'école dont le user est admin.
--
-- 2) « quand on suspend un prof ses notes disparaissent du casier »
--    Cause : get_school_casier_notes filtre strict e.establishment_id = X
--    → OK. Mais il ne vérifie pas m.is_active donc les notes doivent
--    rester. Rappel explicite avec commentaire + garantie que la RPC
--    n'a jamais de clause is_active cachée.
-- =============================================================================

-- 1) Corrige la RPC — retourne UNIQUEMENT les membres de l'école admin.
create or replace function public.get_my_establishment_members()
returns table (
  id uuid,
  establishment_id uuid,
  user_id uuid,
  role text,
  matiere text,
  classes text[],
  is_active boolean,
  joined_at timestamptz,
  display_name text,
  email text,
  photo_path text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.id, m.establishment_id, m.user_id, m.role, m.matiere,
    m.classes, m.is_active, m.joined_at,
    p.display_name, p.email, p.photo_path
  from public.establishment_members m
  left join public.profiles p on p.id = m.user_id
  where m.establishment_id = (
    -- École que l'user courant administre (une seule avec strict account_type)
    select mm.establishment_id
      from public.establishment_members mm
     where mm.user_id = auth.uid()
       and mm.role = 'admin'
       and mm.is_active = true
     limit 1
  )
  order by m.joined_at asc;
$$;

grant execute on function public.get_my_establishment_members() to authenticated;

-- 2) Rappelle explicitement la sémantique casier pour prof suspendu :
--    Les notes déjà publiées RESTENT visibles. Seule la consommation de
--    nouveaux crédits + publication de nouvelles notes est bloquée.
--    (Le blocage se fait dans reserve_credit et publish_copy_to_casier
--    qui checkent bien m.is_active — pas ici.)
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

  -- Michel : notes des profs suspendus RESTENT visibles. Pas de check
  -- is_active ici. La suspension bloque uniquement l'écriture (nouvelle
  -- publication + consommation de crédits) via les RPC concernées.
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
    and e.establishment_id = _v_admin_estab
  order by c.published_at desc;
end;
$$;

grant execute on function public.get_school_casier_notes() to authenticated;

-- 3) Idem get_casier_by_teacher — pas de check is_active
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
    and e.establishment_id = _v_estab_id
  group by e.owner_id, p.display_name, p.email
  order by max(c.published_at) desc;
end;
$$;

grant execute on function public.get_casier_by_teacher() to authenticated;
