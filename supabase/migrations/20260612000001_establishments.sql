-- =============================================================================
-- CORRECTIS V2 — Vue Admin Établissement (Phase 2 du contrat)
-- =============================================================================
-- Tables pour les comptes "École/Établissement" :
--   • establishments       : l'école elle-même (avec son admin owner)
--   • establishment_members: lien user ↔ établissement avec rôle (admin/teacher)
--   • establishment_invitations : invitations email avec token + expiration 48h
--
-- Flux :
--   1. Une école souscrit un plan → établissement créé + user owner = admin
--   2. L'admin invite des enseignants (email) → invitation 48h
--   3. L'enseignant clique le lien → crée son compte → devient member 'teacher'
--   4. Toutes les copies/notes des teachers sont visibles par l'admin (RLS)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. ESTABLISHMENTS
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.establishments (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  city         text,
  country      text default 'Tunisie',
  plan         text not null default 'trial', -- 'trial', 'school', 'lycee', 'university'
  status       text not null default 'active', -- 'active', 'suspended', 'cancelled'
  owner_id     uuid not null references auth.users(id) on delete cascade,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists establishments_owner_id_idx on public.establishments(owner_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. ESTABLISHMENT MEMBERS
-- ─────────────────────────────────────────────────────────────────────────────
-- Un user peut être membre de plusieurs établissements (rare mais possible).
-- Le rôle 'admin' est l'owner ; 'teacher' est un enseignant invité.

create table if not exists public.establishment_members (
  id               uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references public.establishments(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  role             text not null check (role in ('admin', 'teacher')),
  matiere          text, -- principal pour les teachers (Maths, Physique, etc.)
  classes          text[], -- classes assignées (ex: {'3ème A', 'Term. S'})
  is_active        boolean not null default true,
  joined_at        timestamptz not null default now(),
  unique(establishment_id, user_id)
);

create index if not exists establishment_members_user_id_idx on public.establishment_members(user_id);
create index if not exists establishment_members_establishment_id_idx on public.establishment_members(establishment_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. INVITATIONS
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.establishment_invitations (
  id               uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references public.establishments(id) on delete cascade,
  email            text not null,
  matiere          text,
  classes          text[],
  token            text not null unique default encode(gen_random_bytes(24), 'hex'),
  invited_by       uuid not null references auth.users(id),
  expires_at       timestamptz not null default (now() + interval '48 hours'),
  accepted_at      timestamptz,
  accepted_by      uuid references auth.users(id),
  created_at       timestamptz not null default now()
);

create index if not exists invitations_token_idx on public.establishment_invitations(token);
create index if not exists invitations_email_idx on public.establishment_invitations(email);
create index if not exists invitations_establishment_idx on public.establishment_invitations(establishment_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RLS — Row Level Security
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.establishments enable row level security;
alter table public.establishment_members enable row level security;
alter table public.establishment_invitations enable row level security;

-- ESTABLISHMENTS
-- Tout membre peut voir son établissement
drop policy if exists "Members can view their establishment" on public.establishments;
create policy "Members can view their establishment" on public.establishments
  for select using (
    id in (
      select establishment_id from public.establishment_members
      where user_id = auth.uid()
    )
  );

-- Seul l'admin peut update les infos de l'école
drop policy if exists "Admin can update establishment" on public.establishments;
create policy "Admin can update establishment" on public.establishments
  for update using (
    id in (
      select establishment_id from public.establishment_members
      where user_id = auth.uid() and role = 'admin'
    )
  );

-- Tout user authentifié peut créer une école (= devenir admin owner)
drop policy if exists "Authenticated can create establishment" on public.establishments;
create policy "Authenticated can create establishment" on public.establishments
  for insert with check (auth.uid() = owner_id);

-- ESTABLISHMENT MEMBERS
-- Tout membre voit les autres membres de la même école
drop policy if exists "Members visible to same establishment" on public.establishment_members;
create policy "Members visible to same establishment" on public.establishment_members
  for select using (
    establishment_id in (
      select establishment_id from public.establishment_members
      where user_id = auth.uid()
    )
  );

-- Seul l'admin peut inviter/retirer des membres
drop policy if exists "Admin can manage members" on public.establishment_members;
create policy "Admin can manage members" on public.establishment_members
  for all using (
    establishment_id in (
      select establishment_id from public.establishment_members
      where user_id = auth.uid() and role = 'admin'
    )
  );

-- Un user peut s'ajouter lui-même comme teacher si une invitation valide existe
-- (vérifiée côté Edge Function ou trigger)
drop policy if exists "Self insert as teacher" on public.establishment_members;
create policy "Self insert as teacher" on public.establishment_members
  for insert with check (
    user_id = auth.uid() and role = 'teacher'
  );

-- INVITATIONS
-- Admin de l'école voit les invitations qu'il a créées
drop policy if exists "Admin sees own establishment invitations" on public.establishment_invitations;
create policy "Admin sees own establishment invitations" on public.establishment_invitations
  for select using (
    establishment_id in (
      select establishment_id from public.establishment_members
      where user_id = auth.uid() and role = 'admin'
    )
  );

-- Admin crée des invitations pour son école
drop policy if exists "Admin creates invitations" on public.establishment_invitations;
create policy "Admin creates invitations" on public.establishment_invitations
  for insert with check (
    establishment_id in (
      select establishment_id from public.establishment_members
      where user_id = auth.uid() and role = 'admin'
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. RLS sur exams/copies — l'admin voit aussi les exams de ses teachers
-- ─────────────────────────────────────────────────────────────────────────────
-- On enrichit les policies existantes pour qu'un admin d'établissement voie
-- tous les examens (et copies) de ses teachers, en plus de ses propres examens.

drop policy if exists "Admin sees teachers exams" on public.exams;
create policy "Admin sees teachers exams" on public.exams
  for select using (
    owner_id in (
      select m.user_id from public.establishment_members m
      where m.establishment_id in (
        select establishment_id from public.establishment_members
        where user_id = auth.uid() and role = 'admin'
      )
    )
  );

drop policy if exists "Admin sees teachers copies" on public.student_copies;
create policy "Admin sees teachers copies" on public.student_copies
  for select using (
    exam_id in (
      select e.id from public.exams e
      where e.owner_id in (
        select m.user_id from public.establishment_members m
        where m.establishment_id in (
          select establishment_id from public.establishment_members
          where user_id = auth.uid() and role = 'admin'
        )
      )
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Trigger : auto-create admin member quand un établissement est créé
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.handle_new_establishment()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.establishment_members(establishment_id, user_id, role)
  values (new.id, new.owner_id, 'admin')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_establishment_created on public.establishments;
create trigger on_establishment_created
  after insert on public.establishments
  for each row execute function public.handle_new_establishment();
