-- =============================================================================
-- FIX critique : policies "Admin sees teachers exams" et "Admin sees teachers
-- copies" déclenchent une récursion silencieuse sur establishment_members.
-- =============================================================================
-- Symptôme observé : un user authentifié n'arrive plus à lire SES PROPRES
-- examens (pourtant la policy `select_own_exams` est correcte) parce qu'une
-- AUTRE policy SELECT cross-table fait un `from public.establishment_members`
-- direct. Comme Postgres évalue toutes les policies du même type ensemble,
-- si UNE d'entre elles plante (récursion), TOUTE la requête est rejetée.
--
-- Solution : encapsuler la logique "quels user_ids sont teachers d'écoles
-- où je suis admin" dans une fonction SECURITY DEFINER qui bypass les RLS.
-- =============================================================================

-- Fonction helper : retourne les user_ids des teachers que peut voir
-- l'admin courant. Bypass RLS via SECURITY DEFINER.
create or replace function public.user_admin_teachers_ids(uid uuid)
returns setof uuid
language sql
security definer
set search_path = public
stable
as $$
  select m.user_id
  from public.establishment_members m
  where m.establishment_id in (
    select establishment_id
    from public.establishment_members
    where user_id = uid and role = 'admin'
  );
$$;

grant execute on function public.user_admin_teachers_ids(uuid) to authenticated;

-- Recrée les policies sans faire de SELECT direct sur establishment_members
drop policy if exists "Admin sees teachers exams" on public.exams;
create policy "Admin sees teachers exams" on public.exams
  for select using (
    owner_id in (select public.user_admin_teachers_ids(auth.uid()))
  );

drop policy if exists "Admin sees teachers copies" on public.student_copies;
create policy "Admin sees teachers copies" on public.student_copies
  for select using (
    exam_id in (
      select e.id from public.exams e
      where e.owner_id in (
        select public.user_admin_teachers_ids(auth.uid())
      )
    )
  );
