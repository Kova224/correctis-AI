-- =============================================================================
-- Expose la colonne matieres[] dans get_my_memberships pour que le client
-- Flutter puisse filtrer la création d'examen par les matières attribuées
-- à ce prof dans CHAQUE école (multi-école).
-- =============================================================================

drop function if exists public.get_my_memberships();

create function public.get_my_memberships()
returns table (
  out_membership_id uuid,
  out_establishment_id uuid,
  out_establishment_name text,
  out_establishment_city text,
  out_role text,
  out_matiere text,
  out_matieres text[],
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
    m.matieres,
    m.classes,
    m.is_active,
    m.joined_at
  from public.establishment_members m
  join public.establishments e on e.id = m.establishment_id
  where m.user_id = auth.uid()
  order by m.joined_at asc;
$$;

grant execute on function public.get_my_memberships() to authenticated;
