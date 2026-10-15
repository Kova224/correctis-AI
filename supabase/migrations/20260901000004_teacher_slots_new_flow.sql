-- =============================================================================
-- Nouveau flow d'invitation prof (retour Michel) — email + identifiant
--
-- CONTEXTE :
-- L'ancien système utilise un lien correctis://invite?token=XXX transmis par
-- WhatsApp / SMS. Fragile : les liens sont parfois coupés par WhatsApp,
-- non intuitif, et il faut installer l'app avant de cliquer.
--
-- NOUVEAU FLOW :
--   1. L'admin CRÉE dans son école un "slot" prof avec :
--      - email école (ex: math.michel@lycee-cote.fr)
--      - join_code (identifiant unique choisi par admin, ex: LYC-MK-001)
--      - nom du prof
--      - matières attribuées (liste — le prof ne pourra corriger que ces
--        matières dans cette école)
--   2. L'admin communique ces 2 valeurs au prof
--   3. Le prof s'inscrit à Correctis avec son email PERSO
--   4. Dans son profil, il fait "Joindre une école" → 2 champs
--   5. Match (email école + join_code) → création membership + attribution
--      des matières
--   6. Notification admin envoyée à chaque "join" (audit + sécurité)
--
-- MIGRATION DES DONNÉES :
--   - Les invitations token en attente sont PURGÉES (Michel valide).
--   - Les memberships existants (déjà claimés) sont conservés.
-- =============================================================================

-- 1. Nouvelle table teacher_slots
create table if not exists public.establishment_teacher_slots (
  id               uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references public.establishments(id) on delete cascade,
  school_email     text not null,                       -- email attribué par l'école
  join_code        text not null,                       -- identifiant unique choisi par l'admin
  teacher_name     text not null,
  matieres         text[] not null default '{}',        -- codes ExamType (ex: {'math','sciences'})
  status           text not null default 'pending'
                     check (status in ('pending', 'claimed', 'suspended')),
  claimed_by_user_id uuid references auth.users(id) on delete set null,
  claimed_at       timestamptz,
  created_by       uuid not null references auth.users(id),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique(establishment_id, school_email),
  unique(establishment_id, join_code)
);

create index if not exists teacher_slots_establishment_idx
  on public.establishment_teacher_slots(establishment_id);
create index if not exists teacher_slots_claimed_by_idx
  on public.establishment_teacher_slots(claimed_by_user_id);

alter table public.establishment_teacher_slots enable row level security;

drop policy if exists "slots deny" on public.establishment_teacher_slots;
create policy "slots deny"
  on public.establishment_teacher_slots for all using (false);

-- 2. Ajout d'une colonne matieres[] sur establishment_members
--    pour la restriction de correction par matière.
alter table public.establishment_members
  add column if not exists matieres text[] not null default '{}';

-- 3. RPC : admin_create_teacher_slot
--    L'admin crée un slot avec email école + identifiant + matières
create or replace function public.admin_create_teacher_slot(
  p_school_email text,
  p_join_code text,
  p_teacher_name text,
  p_matieres text[] default '{}'
)
returns table (
  out_slot_id uuid,
  out_school_email text,
  out_join_code text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
  _v_slot_id uuid;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;

  -- Vérifie que l'user est admin d'une école
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then
    raise exception 'Action réservée à un admin d''école.';
  end if;

  -- Normalisation
  p_school_email := lower(trim(p_school_email));
  p_join_code := upper(trim(p_join_code));
  p_teacher_name := trim(p_teacher_name);

  if p_school_email = '' or p_join_code = '' or p_teacher_name = '' then
    raise exception 'Email, identifiant et nom sont obligatoires.';
  end if;

  -- Vérifie unicité (établissement, email)
  if exists (
    select 1 from public.establishment_teacher_slots
    where establishment_id = _v_estab_id
      and school_email = p_school_email
  ) then
    raise exception 'Un compte existe déjà pour cet email dans cette école.';
  end if;

  -- Vérifie unicité (établissement, join_code)
  if exists (
    select 1 from public.establishment_teacher_slots
    where establishment_id = _v_estab_id
      and join_code = p_join_code
  ) then
    raise exception 'Cet identifiant est déjà utilisé dans cette école.';
  end if;

  insert into public.establishment_teacher_slots (
    establishment_id, school_email, join_code, teacher_name,
    matieres, created_by
  )
  values (
    _v_estab_id, p_school_email, p_join_code, p_teacher_name,
    coalesce(p_matieres, '{}'), _v_user_id
  )
  returning id into _v_slot_id;

  out_slot_id := _v_slot_id;
  out_school_email := p_school_email;
  out_join_code := p_join_code;
  return next;
end;
$$;

grant execute on function public.admin_create_teacher_slot(text, text, text, text[])
  to authenticated;

-- 4. RPC : admin_update_teacher_slot
create or replace function public.admin_update_teacher_slot(
  p_slot_id uuid,
  p_teacher_name text default null,
  p_matieres text[] default null,
  p_school_email text default null,
  p_join_code text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then raise exception 'Réservé admin.'; end if;

  update public.establishment_teacher_slots
    set
      teacher_name = coalesce(trim(p_teacher_name), teacher_name),
      matieres = coalesce(p_matieres, matieres),
      school_email = coalesce(lower(trim(p_school_email)), school_email),
      join_code = coalesce(upper(trim(p_join_code)), join_code),
      updated_at = now()
    where id = p_slot_id and establishment_id = _v_estab_id;

  -- Si le slot a été claimé, synchronise aussi les matières sur le membership
  update public.establishment_members m
    set matieres = coalesce(p_matieres, m.matieres),
        matiere  = case
          when coalesce(p_matieres, m.matieres) = '{}'::text[]
            then m.matiere
          else (coalesce(p_matieres, m.matieres))[1]
        end
    from public.establishment_teacher_slots s
    where s.id = p_slot_id
      and s.establishment_id = _v_estab_id
      and s.claimed_by_user_id = m.user_id
      and m.establishment_id = s.establishment_id;
end;
$$;

grant execute on function public.admin_update_teacher_slot(uuid, text, text[], text, text)
  to authenticated;

-- 5. RPC : admin_delete_teacher_slot
create or replace function public.admin_delete_teacher_slot(p_slot_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then raise exception 'Réservé admin.'; end if;

  -- Retire aussi le membership s'il existe
  update public.establishment_members m
    set is_active = false
    from public.establishment_teacher_slots s
    where s.id = p_slot_id
      and s.establishment_id = _v_estab_id
      and s.claimed_by_user_id = m.user_id
      and m.establishment_id = s.establishment_id;

  delete from public.establishment_teacher_slots
  where id = p_slot_id and establishment_id = _v_estab_id;
end;
$$;

grant execute on function public.admin_delete_teacher_slot(uuid) to authenticated;

-- 6. RPC : admin_list_teacher_slots (voir tous les slots de mon école)
drop function if exists public.admin_list_teacher_slots();
create function public.admin_list_teacher_slots()
returns table (
  out_slot_id uuid,
  out_school_email text,
  out_join_code text,
  out_teacher_name text,
  out_matieres text[],
  out_status text,
  out_claimed_by_user_id uuid,
  out_claimed_at timestamptz,
  out_created_at timestamptz
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
  select s.id, s.school_email, s.join_code, s.teacher_name,
         s.matieres, s.status, s.claimed_by_user_id, s.claimed_at,
         s.created_at
  from public.establishment_teacher_slots s
  where s.establishment_id = _v_estab_id
  order by s.created_at desc;
end;
$$;

grant execute on function public.admin_list_teacher_slots() to authenticated;

-- 7. RPC : teacher_join_school (le prof rejoint via email + code)
create or replace function public.teacher_join_school(
  p_school_email text,
  p_join_code text
)
returns table (
  out_ok boolean,
  out_reason text,
  out_establishment_id uuid,
  out_establishment_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_slot record;
  _v_estab record;
begin
  if _v_user_id is null then
    out_ok := false; out_reason := 'NOT_AUTHENTICATED';
    return next; return;
  end if;

  p_school_email := lower(trim(p_school_email));
  p_join_code := upper(trim(p_join_code));

  -- Cherche le slot correspondant
  select * into _v_slot
  from public.establishment_teacher_slots
  where school_email = p_school_email and join_code = p_join_code;

  if _v_slot is null then
    out_ok := false; out_reason := 'SLOT_NOT_FOUND';
    return next; return;
  end if;

  if _v_slot.status = 'claimed' and _v_slot.claimed_by_user_id != _v_user_id then
    out_ok := false; out_reason := 'ALREADY_CLAIMED_BY_OTHER';
    return next; return;
  end if;

  if _v_slot.status = 'suspended' then
    out_ok := false; out_reason := 'SLOT_SUSPENDED';
    return next; return;
  end if;

  -- Marque le slot claimé
  update public.establishment_teacher_slots
    set status = 'claimed',
        claimed_by_user_id = _v_user_id,
        claimed_at = coalesce(claimed_at, now()),
        updated_at = now()
    where id = _v_slot.id;

  -- Crée / réactive le membership
  insert into public.establishment_members (
    establishment_id, user_id, role, matiere, matieres, is_active
  )
  values (
    _v_slot.establishment_id, _v_user_id, 'teacher',
    coalesce(_v_slot.matieres[1], null),
    coalesce(_v_slot.matieres, '{}'),
    true
  )
  on conflict (establishment_id, user_id)
    do update set
      is_active = true,
      matiere = coalesce(excluded.matiere, establishment_members.matiere),
      matieres = coalesce(excluded.matieres, establishment_members.matieres);

  -- Charge l'école pour la réponse
  select id, name into _v_estab
  from public.establishments where id = _v_slot.establishment_id;

  -- Notification admin(s) : "X a rejoint votre école via le code"
  insert into public.notifications (
    user_id, establishment_id, kind, title, body, ref_id
  )
  select
    m.user_id,
    _v_slot.establishment_id,
    'member_joined',
    'Nouvel enseignant rejoint',
    _v_slot.teacher_name || ' a rejoint votre école via le code ' || _v_slot.join_code || '.',
    _v_slot.id::text
  from public.establishment_members m
  where m.establishment_id = _v_slot.establishment_id
    and m.role = 'admin'
    and m.is_active = true
  on conflict do nothing;

  out_ok := true;
  out_reason := 'OK';
  out_establishment_id := _v_estab.id;
  out_establishment_name := _v_estab.name;
  return next;
end;
$$;

grant execute on function public.teacher_join_school(text, text) to authenticated;

-- 8. RPC : teacher_leave_school (le prof quitte volontairement)
create or replace function public.teacher_leave_school(p_establishment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  -- Marque le membership inactif (soft leave — l'admin voit qu'il a quitté)
  update public.establishment_members
    set is_active = false
    where user_id = _v_user_id and establishment_id = p_establishment_id;
  -- Libère le slot pour qu'un autre prof puisse le réutiliser
  update public.establishment_teacher_slots
    set status = 'pending',
        claimed_by_user_id = null,
        claimed_at = null,
        updated_at = now()
    where establishment_id = p_establishment_id
      and claimed_by_user_id = _v_user_id;
end;
$$;

grant execute on function public.teacher_leave_school(uuid) to authenticated;

-- 9. RPC : admin_toggle_slot_status (suspend / réactive un slot)
create or replace function public.admin_toggle_slot_status(
  p_slot_id uuid,
  p_new_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if p_new_status not in ('pending', 'claimed', 'suspended') then
    raise exception 'Statut invalide.';
  end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then raise exception 'Réservé admin.'; end if;

  update public.establishment_teacher_slots
    set status = p_new_status, updated_at = now()
    where id = p_slot_id and establishment_id = _v_estab_id;

  -- Répercute sur le membership si le slot est claimé
  update public.establishment_members m
    set is_active = (p_new_status != 'suspended')
    from public.establishment_teacher_slots s
    where s.id = p_slot_id
      and s.establishment_id = _v_estab_id
      and s.claimed_by_user_id = m.user_id
      and m.establishment_id = s.establishment_id;
end;
$$;

grant execute on function public.admin_toggle_slot_status(uuid, text) to authenticated;

-- 10. Purge des anciennes invitations token en attente (retour Michel)
delete from public.establishment_invitations where accepted_at is null;

-- 11. Ajoute 'member_joined' comme kind valide si notifications a un check
--     (best-effort, ignoré si contrainte inexistante)
do $$
begin
  begin
    -- Certains schemas ont un CHECK sur kind. On l'élargit si présent.
    alter table public.notifications drop constraint if exists notifications_kind_check;
  exception when others then
    -- ignore
    null;
  end;
end $$;
