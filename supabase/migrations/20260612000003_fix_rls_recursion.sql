-- =============================================================================
-- FIX : Infinite recursion sur les RLS de establishment_members
-- =============================================================================
-- Les policies de la migration 20260612000001 faisaient un SELECT sur la même
-- table qu'elles protègent (establishment_members), ce qui crée une récursion
-- infinie dans Postgres :
--
--   create policy "..." on establishment_members
--     for select using (
--       establishment_id in (
--         select establishment_id from establishment_members  -- ⚠ même table
--         where user_id = auth.uid()
--       )
--     );
--
-- Solution standard : extraire la requête dans une fonction SECURITY DEFINER
-- qui bypasse les RLS lors de son exécution. Les policies peuvent alors
-- l'appeler sans déclencher la récursion.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Fonctions helper (bypass RLS)
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.user_establishments(uid uuid)
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select establishment_id
  from public.establishment_members
  where user_id = uid;
$$;

create or replace function public.user_admin_establishments(uid uuid)
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select establishment_id
  from public.establishment_members
  where user_id = uid and role = 'admin';
$$;

-- Permet aux users authentifiés d'appeler ces fonctions
grant execute on function public.user_establishments(uuid) to authenticated;
grant execute on function public.user_admin_establishments(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Reset des policies + recréation sans récursion
-- ─────────────────────────────────────────────────────────────────────────────

-- establishments
drop policy if exists "Members can view their establishment" on public.establishments;
create policy "Members can view their establishment" on public.establishments
  for select using (
    id in (select public.user_establishments(auth.uid()))
  );

drop policy if exists "Admin can update establishment" on public.establishments;
create policy "Admin can update establishment" on public.establishments
  for update using (
    id in (select public.user_admin_establishments(auth.uid()))
  );

-- establishment_members
drop policy if exists "Members visible to same establishment" on public.establishment_members;
create policy "Members visible to same establishment" on public.establishment_members
  for select using (
    establishment_id in (select public.user_establishments(auth.uid()))
  );

drop policy if exists "Admin can manage members" on public.establishment_members;
create policy "Admin can manage members" on public.establishment_members
  for all using (
    establishment_id in (select public.user_admin_establishments(auth.uid()))
  );

-- establishment_invitations
drop policy if exists "Admin sees own establishment invitations" on public.establishment_invitations;
create policy "Admin sees own establishment invitations" on public.establishment_invitations
  for select using (
    establishment_id in (select public.user_admin_establishments(auth.uid()))
  );

drop policy if exists "Admin creates invitations" on public.establishment_invitations;
create policy "Admin creates invitations" on public.establishment_invitations
  for insert with check (
    establishment_id in (select public.user_admin_establishments(auth.uid()))
  );

drop policy if exists "Admin can delete invitations" on public.establishment_invitations;
create policy "Admin can delete invitations" on public.establishment_invitations
  for delete using (
    establishment_id in (select public.user_admin_establishments(auth.uid()))
  );

drop policy if exists "Admin can update invitations" on public.establishment_invitations;
create policy "Admin can update invitations" on public.establishment_invitations
  for update using (
    establishment_id in (select public.user_admin_establishments(auth.uid()))
  );

-- Cross-table : admin voit les exams + copies de ses teachers
drop policy if exists "Admin sees teachers exams" on public.exams;
create policy "Admin sees teachers exams" on public.exams
  for select using (
    owner_id in (
      select m.user_id
      from public.establishment_members m
      where m.establishment_id in (
        select public.user_admin_establishments(auth.uid())
      )
    )
  );

drop policy if exists "Admin sees teachers copies" on public.student_copies;
create policy "Admin sees teachers copies" on public.student_copies
  for select using (
    exam_id in (
      select e.id
      from public.exams e
      where e.owner_id in (
        select m.user_id
        from public.establishment_members m
        where m.establishment_id in (
          select public.user_admin_establishments(auth.uid())
        )
      )
    )
  );
