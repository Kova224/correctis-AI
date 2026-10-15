-- =============================================================================
-- FIX : Fonction RPC bypass RLS pour retourner l'appartenance de l'user
-- =============================================================================
-- Symptôme : un user authentifié pourtant admin en DB (vérifié via service_role)
-- n'arrive pas à lire sa ligne dans establishment_members depuis l'app. Cause
-- probable : interaction RLS complexe ou auth.uid() qui ne propage pas
-- correctement dans la requête.
--
-- Solution : exposer une fonction RPC SECURITY DEFINER qui retourne les
-- infos directement, sans passer par les RLS de la table. Plus robuste,
-- plus simple, plus rapide.
-- =============================================================================

create or replace function public.get_my_membership()
returns table (
  membership_id uuid,
  establishment_id uuid,
  user_id uuid,
  role text,
  is_active boolean,
  matiere text,
  classes text[],
  joined_at timestamptz,
  establishment_name text,
  establishment_city text,
  establishment_country text,
  establishment_plan text,
  establishment_status text,
  establishment_config jsonb,
  establishment_owner_id uuid,
  establishment_created_at timestamptz,
  establishment_updated_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.id as membership_id,
    m.establishment_id,
    m.user_id,
    m.role,
    m.is_active,
    m.matiere,
    m.classes,
    m.joined_at,
    e.name as establishment_name,
    e.city as establishment_city,
    e.country as establishment_country,
    e.plan as establishment_plan,
    e.status as establishment_status,
    e.config as establishment_config,
    e.owner_id as establishment_owner_id,
    e.created_at as establishment_created_at,
    e.updated_at as establishment_updated_at
  from public.establishment_members m
  join public.establishments e on e.id = m.establishment_id
  where m.user_id = auth.uid()
  limit 1;
$$;

grant execute on function public.get_my_membership() to authenticated;
