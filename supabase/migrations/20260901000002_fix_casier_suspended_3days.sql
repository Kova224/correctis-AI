-- =============================================================================
-- Correction Michel — Notes des profs suspendus : ne restent visibles au
-- casier QUE si elles ont > 3 jours dans le casier (locked_at < now())
--
-- Ma 1re migration (20260831000001) avait retiré totalement le filtre
-- is_active. Michel affine :
--   - Prof actif → toutes ses notes visibles (comportement inchangé)
--   - Prof suspendu :
--       • Notes verrouillées (publiées depuis > 3 j) → RESTENT visibles
--       • Notes récentes (< 3 j) → cachées (cohérent avec la suspension)
--
-- Rappel : locked_at = published_at + 3 jours (trigger update_locked_at).
--   → locked_at IS NOT NULL AND locked_at < now() = "verrouillée / archivée"
-- =============================================================================

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
    and (
      -- CAS 1 : prof toujours actif → toutes ses notes visibles
      exists (
        select 1 from public.establishment_members m
        where m.establishment_id = _v_estab_id
          and m.user_id = e.owner_id
          and m.is_active = true
      )
      OR
      -- CAS 2 : prof suspendu mais note verrouillée (> 3 j)
      (
        exists (
          select 1 from public.establishment_members m
          where m.establishment_id = _v_estab_id
            and m.user_id = e.owner_id
            and m.is_active = false
        )
        and c.locked_at is not null
        and c.locked_at < now()
      )
      OR
      -- CAS 3 : examen explicitement rattaché à l'école (garde-fou)
      e.establishment_id = _v_estab_id
    )
  group by e.owner_id, p.display_name, p.email
  order by max(c.published_at) desc;
end;
$$;

-- Idem pour get_teacher_classes (niveau 2)
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
  _v_teacher_is_active boolean;
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  -- Le prof cible est-il encore actif dans cette école ?
  select is_active into _v_teacher_is_active
  from public.establishment_members
  where establishment_id = _v_estab_id and user_id = p_teacher_user_id
  limit 1;

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
         or coalesce(_v_teacher_is_active, false) = true
         or (c.locked_at is not null and c.locked_at < now()))
  group by e.class_name
  order by e.class_name;
end;
$$;

grant execute on function public.get_casier_by_teacher() to authenticated;
grant execute on function public.get_teacher_classes(uuid) to authenticated;
