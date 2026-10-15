-- =============================================================================
-- Sprint 2 : Notifications admin→profs + Casier groupé par prof/classe/type
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Table des notifications admin → profs (lecture seule côté profs)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.establishment_notifications (
  id               uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references public.establishments(id) on delete cascade,
  author_user_id   uuid not null references auth.users(id) on delete cascade,
  title            text not null,
  body             text not null,
  -- targets : null = tous les profs de l'école, sinon liste de user_ids ciblés
  targets          uuid[] default null,
  created_at       timestamptz not null default now()
);
create index if not exists notifs_estab_idx
  on public.establishment_notifications(establishment_id);
create index if not exists notifs_created_idx
  on public.establishment_notifications(created_at desc);

-- Table de tracking des lectures par prof
create table if not exists public.establishment_notification_reads (
  notification_id uuid not null references public.establishment_notifications(id) on delete cascade,
  user_id         uuid not null references auth.users(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (notification_id, user_id)
);

alter table public.establishment_notifications enable row level security;
alter table public.establishment_notification_reads enable row level security;

-- RLS minimal : on autorise tout sélect/insert depuis fonctions SECURITY DEFINER.
-- Les utilisateurs passent par les RPC, pas par les tables directement.
drop policy if exists "deny direct read notifs" on public.establishment_notifications;
create policy "deny direct read notifs"
  on public.establishment_notifications for select using (false);

drop policy if exists "deny direct read reads" on public.establishment_notification_reads;
create policy "deny direct read reads"
  on public.establishment_notification_reads for select using (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RPC : Admin crée une notification (ciblée ou broadcast)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.create_notification(
  p_title text,
  p_body text,
  p_targets uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
  _v_notif_id uuid;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then
    raise exception 'Action réservée à l''administrateur.';
  end if;
  if trim(coalesce(p_title, '')) = '' then
    raise exception 'Titre requis.';
  end if;
  if trim(coalesce(p_body, '')) = '' then
    raise exception 'Message requis.';
  end if;

  insert into public.establishment_notifications (
    establishment_id, author_user_id, title, body, targets
  ) values (
    _v_estab_id, _v_user_id, trim(p_title), trim(p_body),
    case when p_targets is null or array_length(p_targets, 1) is null
         then null
         else p_targets
    end
  )
  returning id into _v_notif_id;
  return _v_notif_id;
end;
$$;
grant execute on function public.create_notification(text, text, uuid[]) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RPC : Admin liste les notifications envoyées
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_admin_sent_notifications()
returns table (
  out_id uuid,
  out_title text,
  out_body text,
  out_targets uuid[],
  out_created_at timestamptz,
  out_read_count int,
  out_total_recipients int
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
    n.id,
    n.title,
    n.body,
    n.targets,
    n.created_at,
    (select count(*)::int
       from public.establishment_notification_reads r
       where r.notification_id = n.id),
    coalesce(array_length(n.targets, 1),
             (select count(*)::int
              from public.establishment_members
              where establishment_id = _v_estab_id
                and role = 'teacher'
                and is_active = true))
  from public.establishment_notifications n
  where n.establishment_id = _v_estab_id
  order by n.created_at desc;
end;
$$;
grant execute on function public.get_admin_sent_notifications() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RPC : Prof liste ses notifications reçues
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_notifications()
returns table (
  out_id uuid,
  out_establishment_name text,
  out_author_name text,
  out_title text,
  out_body text,
  out_created_at timestamptz,
  out_read_at timestamptz
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
    n.id,
    e.name,
    coalesce(p.display_name, p.email, 'Administrateur'),
    n.title,
    n.body,
    n.created_at,
    r.read_at
  from public.establishment_notifications n
  join public.establishments e on e.id = n.establishment_id
  left join public.profiles p on p.id = n.author_user_id
  left join public.establishment_notification_reads r
    on r.notification_id = n.id and r.user_id = _v_user_id
  where n.establishment_id in (
    select establishment_id from public.establishment_members
    where user_id = _v_user_id and is_active = true
  )
  and (n.targets is null or _v_user_id = any(n.targets))
  order by n.created_at desc;
end;
$$;
grant execute on function public.get_my_notifications() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RPC : marquer une notification comme lue
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.mark_notification_read(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then return; end if;
  insert into public.establishment_notification_reads (notification_id, user_id)
  values (p_notification_id, _v_user_id)
  on conflict do nothing;
end;
$$;
grant execute on function public.mark_notification_read(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RPC : Admin liste ses profs avec nombre de notes envoyées par chacun
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
           select user_id from public.establishment_members
           where establishment_id = _v_estab_id and is_active = true
         ))
  group by e.owner_id, p.display_name, p.email
  order by max(c.published_at) desc;
end;
$$;
grant execute on function public.get_casier_by_teacher() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. RPC : Admin liste les classes d'un prof précis (avec compte notes)
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
           select user_id from public.establishment_members
           where establishment_id = _v_estab_id and is_active = true
         ))
  group by e.class_name
  order by e.class_name;
end;
$$;
grant execute on function public.get_teacher_classes(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. RPC : notes d'une classe d'un prof, filtrées par type de contrôle
-- ─────────────────────────────────────────────────────────────────────────────
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
  order by c.published_at desc;
end;
$$;
grant execute on function public.get_class_notes(uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. RPC : relevé d'un élève par type de contrôle
-- ─────────────────────────────────────────────────────────────────────────────
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
    and lower(c.student_name) like '%' || lower(p_student_name) || '%'
    and (p_student_ref is null or
         lower(coalesce(c.student_ref, '')) = lower(p_student_ref))
    and (p_control_type is null or
         coalesce(e.control_type, 'general') = p_control_type)
    and e.owner_id in (
      select user_id from public.establishment_members
      where establishment_id = _v_estab_id
    )
  order by c.published_at desc;
end;
$$;
grant execute on function public.get_student_releve(text, text, text) to authenticated;
