-- =============================================================================
-- B1 (Sprint 2) — Correctif : les notes des profs SUSPENDUS restent visibles
--                dans le casier numérique.
--
-- CONTEXTE (retour Michel) : "Quand l'admin suspend un prof, les notes de ce
-- prof disparaissent dans le casier alors que ça ne devrait pas disparaître."
--
-- CAUSE :
--   - `get_casier_by_teacher` filtrait `is_active = true` dans le sous-select
--     des membres de l'école → prof suspendu invisible en agrégation.
--   - `get_teacher_classes` avait le même filtre.
--
-- FIX : on retire `is_active = true` de ces 2 RPCs de LECTURE historique.
--       L'écriture (create/publish) reste bloquée pour profs suspendus
--       (filtres dans les autres RPCs).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. get_casier_by_teacher : liste des profs (niveau 1 du casier)
-- ─────────────────────────────────────────────────────────────────────────────
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
    and (e.establishment_id = _v_estab_id
         or e.owner_id in (
           -- B1 FIX : on retire "is_active = true" pour que les notes des
           -- profs suspendus restent visibles dans le casier (archive).
           select user_id from public.establishment_members
           where establishment_id = _v_estab_id
         ))
  group by e.owner_id, p.display_name, p.email
  order by max(c.published_at) desc;
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. get_teacher_classes : classes d'un prof (niveau 2 du casier)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_teacher_classes(p_teacher_user_id uuid)
returns table (
  out_class_name text,
  out_notes_count int,
  out_control_types text[]
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
    array_agg(distinct coalesce(e.control_type, 'general'))
  from public.exams e
  join public.student_copies c on c.exam_id = e.id
  where c.published_at is not null
    and c.status = 'graded'
    and e.owner_id = p_teacher_user_id
    and (e.establishment_id = _v_estab_id
         or p_teacher_user_id in (
           -- B1 FIX : on retire "is_active = true" pour que les classes des
           -- profs suspendus restent visibles dans le casier (archive).
           select user_id from public.establishment_members
           where establishment_id = _v_estab_id
         ))
  group by e.class_name
  order by e.class_name;
end;
$$;

grant execute on function public.get_casier_by_teacher() to authenticated;
grant execute on function public.get_teacher_classes(uuid) to authenticated;
