-- =============================================================================
-- FIX doublon "École X" dans le sélecteur de création d'examen.
-- Un même user peut avoir 2 rows dans establishment_members pour la même
-- école (admin + teacher, ou 2 teachers créés accidentellement). Le sélecteur
-- affichait alors l'école deux fois.
--
-- Solution : dedupe côté RPC. On garde 1 seule ligne par (user, école) avec
-- le rôle le plus élevé (admin > teacher) et l'union des matieres/classes.
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
  with ranked as (
    select
      m.*,
      e.name as e_name,
      e.city as e_city,
      -- admin > teacher (rang le plus bas gagne)
      case when m.role = 'admin' then 0 else 1 end as role_rank,
      row_number() over (
        partition by m.establishment_id
        order by
          case when m.role = 'admin' then 0 else 1 end asc,
          m.is_active desc,
          m.joined_at asc
      ) as rn
    from public.establishment_members m
    join public.establishments e on e.id = m.establishment_id
    where m.user_id = auth.uid()
  )
  select
    id,
    establishment_id,
    e_name,
    e_city,
    role,
    matiere,
    matieres,
    classes,
    is_active,
    joined_at
  from ranked
  where rn = 1
  order by joined_at asc;
$$;

grant execute on function public.get_my_memberships() to authenticated;
