-- =============================================================================
-- Sprint 1 : Multi-établissement + Types de contrôle + Verrouillage 3 jours +
--            Suspension prof
-- =============================================================================
-- Changements DB pour supporter :
--   • Un prof rattaché à plusieurs écoles (déjà OK : establishment_members
--     permet plusieurs lignes par user_id). Ajout d'un champ pour
--     stocker l'école active côté serveur.
--   • Type de contrôle par examen (DS, Examen, Bac blanc, etc.) +
--     rattachement de l'examen à une école précise.
--   • Verrouillage des copies publiées après 3 jours.
--   • RPC pour suspendre/réactiver un membre.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. EXAMS : ajout du type de contrôle + école de rattachement
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.exams
  add column if not exists control_type text default 'general',
  add column if not exists establishment_id uuid references public.establishments(id) on delete set null;

-- Index pour requêtes admin sur le casier
create index if not exists exams_establishment_idx
  on public.exams(establishment_id) where establishment_id is not null;
create index if not exists exams_control_type_idx
  on public.exams(control_type);

comment on column public.exams.control_type is
  'Type de contrôle : ds, examen, bac_blanc, devoir_maison, oral, etc.';
comment on column public.exams.establishment_id is
  'École à laquelle est rattaché cet examen. Null = examen prof solo.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. STUDENT_COPIES : verrouillage après 3 jours
-- ─────────────────────────────────────────────────────────────────────────────
-- locked_at = published_at + 3 jours (calculé via trigger, ou côté code)
alter table public.student_copies
  add column if not exists locked_at timestamptz;

-- Trigger : à chaque update de published_at, met locked_at = published_at + 3j
create or replace function public.update_locked_at()
returns trigger
language plpgsql
as $$
begin
  if NEW.published_at is not null and NEW.published_at is distinct from OLD.published_at then
    NEW.locked_at := NEW.published_at + interval '3 days';
  elsif NEW.published_at is null then
    NEW.locked_at := null;
  end if;
  return NEW;
end;
$$;

drop trigger if exists on_published_at_update on public.student_copies;
create trigger on_published_at_update
  before update on public.student_copies
  for each row execute function public.update_locked_at();

-- Rétroactivement : copies déjà publiées → calcule locked_at
update public.student_copies
set locked_at = published_at + interval '3 days'
where published_at is not null and locked_at is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RPC suspend / unsuspend un membre (admin seulement)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.suspend_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;
  -- Vérifie que je suis admin de l'école de ce membre
  select establishment_id into _v_estab_id
  from public.establishment_members
  where id = p_member_id;
  if _v_estab_id is null then
    raise exception 'Membre introuvable.';
  end if;
  if not exists (
    select 1 from public.establishment_members
    where user_id = _v_user_id
      and establishment_id = _v_estab_id
      and role = 'admin'
      and is_active = true
  ) then
    raise exception 'Action réservée à l''administrateur de l''école.';
  end if;
  update public.establishment_members
  set is_active = false
  where id = p_member_id;
end;
$$;
grant execute on function public.suspend_member(uuid) to authenticated;

create or replace function public.unsuspend_member(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where id = p_member_id;
  if _v_estab_id is null then
    raise exception 'Membre introuvable.';
  end if;
  if not exists (
    select 1 from public.establishment_members
    where user_id = _v_user_id
      and establishment_id = _v_estab_id
      and role = 'admin'
      and is_active = true
  ) then
    raise exception 'Action réservée à l''administrateur de l''école.';
  end if;
  update public.establishment_members
  set is_active = true
  where id = p_member_id;
end;
$$;
grant execute on function public.unsuspend_member(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RPC liste de TOUTES les écoles d'un user (multi-établissement)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_memberships()
returns table (
  out_membership_id uuid,
  out_establishment_id uuid,
  out_establishment_name text,
  out_establishment_city text,
  out_role text,
  out_matiere text,
  out_classes text[],
  out_is_active boolean,
  out_joined_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.id,
    e.id,
    e.name,
    e.city,
    m.role,
    m.matiere,
    m.classes,
    m.is_active,
    m.joined_at
  from public.establishment_members m
  join public.establishments e on e.id = m.establishment_id
  where m.user_id = auth.uid()
  order by m.joined_at asc;
$$;
grant execute on function public.get_my_memberships() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Refactor publish_exam_copies pour respecter le verrouillage 3j
-- ─────────────────────────────────────────────────────────────────────────────
-- Important : unpublish_exam_copies doit refuser si la copie est verrouillée
create or replace function public.unpublish_exam_copies(p_exam_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_count int := 0;
  _v_locked_count int := 0;
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

  -- Compte les copies verrouillées (>3j) qu'on ne peut PAS dépublier
  select count(*) into _v_locked_count
  from public.student_copies
  where exam_id = p_exam_id
    and published_at is not null
    and locked_at is not null
    and locked_at < now();

  -- Dépublie uniquement les copies dans la fenêtre des 3j
  update public.student_copies
  set published_at = null
  where exam_id = p_exam_id
    and published_at is not null
    and (locked_at is null or locked_at >= now());

  get diagnostics _v_count = row_count;

  if _v_locked_count > 0 then
    raise notice
      '% copie(s) verrouillée(s) (publiées il y a plus de 3 jours), '
      'elles restent dans le casier.', _v_locked_count;
  end if;
  return _v_count;
end;
$$;
grant execute on function public.unpublish_exam_copies(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RPC : supprimer une copie (refuse si verrouillée)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.delete_copy_safe(p_copy_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_exam_id uuid;
  _v_locked_at timestamptz;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;

  select c.exam_id, c.locked_at into _v_exam_id, _v_locked_at
  from public.student_copies c
  where c.id = p_copy_id;

  if _v_exam_id is null then
    raise exception 'Copie introuvable.';
  end if;

  -- Vérifie que je suis propriétaire de l'examen
  if not exists (
    select 1 from public.exams
    where id = _v_exam_id and owner_id = _v_user_id
  ) then
    raise exception 'Vous n''êtes pas propriétaire de cet examen.';
  end if;

  -- Refuse si la copie est verrouillée (publication > 3 jours)
  if _v_locked_at is not null and _v_locked_at < now() then
    return 'LOCKED';
  end if;

  delete from public.student_copies where id = p_copy_id;
  return 'OK';
end;
$$;
grant execute on function public.delete_copy_safe(uuid) to authenticated;
