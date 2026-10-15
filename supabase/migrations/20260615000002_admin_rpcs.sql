-- =============================================================================
-- RPCs SECURITY DEFINER pour les opérations admin établissement
-- =============================================================================
-- Les policies RLS sur establishment_members provoquent encore des récursions
-- silencieuses dans certaines opérations (insert invitation, list members,
-- etc.). Au lieu de chercher quelle policy boucle, on bascule toutes les
-- opérations métier admin via des fonctions RPC en SECURITY DEFINER. Elles
-- vérifient elles-mêmes le droit de l'appelant et bypass les RLS.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Créer une invitation
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.create_invitation(
  p_email text,
  p_matiere text default null,
  p_classes text[] default array[]::text[]
)
returns table (
  id uuid,
  establishment_id uuid,
  email text,
  matiere text,
  classes text[],
  token text,
  invited_by uuid,
  expires_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_establishment_id uuid;
  v_invitation_id uuid;
begin
  -- Vérifie que l'user est admin actif d'au moins une école
  select m.establishment_id into v_establishment_id
  from public.establishment_members m
  where m.user_id = v_user_id
    and m.role = 'admin'
    and m.is_active = true
  limit 1;

  if v_establishment_id is null then
    raise exception 'Action réservée à l''administrateur de l''école.';
  end if;

  -- Crée l'invitation (token et expires_at via defaults de la table)
  insert into public.establishment_invitations (
    establishment_id, email, matiere, classes, invited_by
  ) values (
    v_establishment_id,
    lower(trim(p_email)),
    nullif(trim(coalesce(p_matiere, '')), ''),
    coalesce(p_classes, array[]::text[]),
    v_user_id
  )
  returning establishment_invitations.id into v_invitation_id;

  return query
  select i.id, i.establishment_id, i.email, i.matiere, i.classes,
         i.token, i.invited_by, i.expires_at, i.accepted_at, i.created_at
  from public.establishment_invitations i
  where i.id = v_invitation_id;
end;
$$;

grant execute on function public.create_invitation(text, text, text[]) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Annuler une invitation
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.cancel_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_is_admin_of boolean;
begin
  -- Vérifie que l'user est admin de l'école de cette invitation
  select exists(
    select 1
    from public.establishment_invitations i
    join public.establishment_members m
      on m.establishment_id = i.establishment_id
    where i.id = p_invitation_id
      and m.user_id = v_user_id
      and m.role = 'admin'
      and m.is_active = true
  ) into v_is_admin_of;

  if not v_is_admin_of then
    raise exception 'Action réservée à l''administrateur de l''école.';
  end if;

  delete from public.establishment_invitations where id = p_invitation_id;
end;
$$;

grant execute on function public.cancel_invitation(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Liste des invitations en attente (admin uniquement)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_pending_invitations()
returns table (
  id uuid,
  establishment_id uuid,
  email text,
  matiere text,
  classes text[],
  token text,
  invited_by uuid,
  expires_at timestamptz,
  accepted_at timestamptz,
  created_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select i.id, i.establishment_id, i.email, i.matiere, i.classes,
         i.token, i.invited_by, i.expires_at, i.accepted_at, i.created_at
  from public.establishment_invitations i
  where i.accepted_at is null
    and i.establishment_id in (
      select m.establishment_id
      from public.establishment_members m
      where m.user_id = auth.uid()
        and m.role = 'admin'
        and m.is_active = true
    )
  order by i.created_at desc;
$$;

grant execute on function public.get_my_pending_invitations() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Liste des membres de mon établissement (avec profil joint)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_establishment_members()
returns table (
  id uuid,
  establishment_id uuid,
  user_id uuid,
  role text,
  matiere text,
  classes text[],
  is_active boolean,
  joined_at timestamptz,
  display_name text,
  email text,
  photo_path text
)
language sql
security definer
set search_path = public
stable
as $$
  select
    m.id, m.establishment_id, m.user_id, m.role, m.matiere,
    m.classes, m.is_active, m.joined_at,
    p.display_name, p.email, p.photo_path
  from public.establishment_members m
  left join public.profiles p on p.id = m.user_id
  where m.establishment_id in (
    select mm.establishment_id
    from public.establishment_members mm
    where mm.user_id = auth.uid()
  )
  order by m.joined_at asc;
$$;

grant execute on function public.get_my_establishment_members() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Mettre à jour la config de l'établissement
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.update_my_establishment_config(p_config jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_establishment_id uuid;
begin
  select m.establishment_id into v_establishment_id
  from public.establishment_members m
  where m.user_id = v_user_id
    and m.role = 'admin'
    and m.is_active = true
  limit 1;

  if v_establishment_id is null then
    raise exception 'Action réservée à l''administrateur de l''école.';
  end if;

  update public.establishments
  set config = p_config, updated_at = now()
  where id = v_establishment_id;
end;
$$;

grant execute on function public.update_my_establishment_config(jsonb) to authenticated;
