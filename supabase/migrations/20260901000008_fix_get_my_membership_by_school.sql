-- =============================================================================
-- FIX CRITIQUE : get_my_membership retournait AU HASARD un des memberships
-- du prof (limit 1 sans filtre). En multi-école, la bascule ne fonctionnait
-- pas car la RPC pouvait retourner la mauvaise école.
--
-- Nouveau : ajoute p_establishment_id optionnel pour cibler explicitement
-- l'école active. Le client Flutter passe l'école persistée dans SharedPrefs.
--
-- Ajoute aussi out_matieres pour compléter le contexte du membership.
-- =============================================================================

drop function if exists public.get_my_membership();
drop function if exists public.get_my_membership(uuid);

create function public.get_my_membership(p_establishment_id uuid default null)
returns table (
  membership_id uuid,
  establishment_id uuid,
  user_id uuid,
  role text,
  is_active boolean,
  matiere text,
  matieres text[],
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
    m.matieres,
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
    and m.is_active = true
    -- Michel : filtre par l'école active si fournie, sinon 1re trouvée
    and (p_establishment_id is null or m.establishment_id = p_establishment_id)
  order by
    -- Prefer l'école active exacte, sinon jointure la plus récente
    case when p_establishment_id is not null
      and m.establishment_id = p_establishment_id then 0 else 1 end,
    m.joined_at desc
  limit 1;
$$;

grant execute on function public.get_my_membership(uuid) to authenticated;
