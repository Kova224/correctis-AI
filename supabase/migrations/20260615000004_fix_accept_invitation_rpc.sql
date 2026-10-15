-- =============================================================================
-- FIX : RPC accept_invitation_rpc — ambiguïté de colonne corrigée
-- =============================================================================
-- Bug : erreur 42702 "column reference 'establishment_id' is ambiguous"
-- parce que les noms des colonnes de la table de retour étaient identiques
-- aux variables internes de la fonction. PostgreSQL ne savait pas si on
-- parlait du record `v_invitation` ou des colonnes RETURNS TABLE.
--
-- Fix : préfixer les variables avec _v_ et les colonnes retour avec out_*.
-- =============================================================================

drop function if exists public.accept_invitation_rpc(text);

create or replace function public.accept_invitation_rpc(p_token text)
returns table (
  out_establishment_id uuid,
  out_establishment_name text,
  out_member_id uuid,
  out_role text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_user_email text;
  _v_inv_id uuid;
  _v_inv_establishment_id uuid;
  _v_inv_email text;
  _v_inv_matiere text;
  _v_inv_classes text[];
  _v_inv_expires_at timestamptz;
  _v_inv_accepted_at timestamptz;
  _v_member_id uuid;
  _v_estab_name text;
begin
  if _v_user_id is null then
    raise exception 'Vous devez être connecté pour accepter l''invitation.';
  end if;

  select email into _v_user_email from auth.users where id = _v_user_id;
  if _v_user_email is null then
    raise exception 'Session invalide.';
  end if;

  -- Lit l'invitation dans des variables scalaires distinctes (évite
  -- toute confusion avec les colonnes de la table de retour).
  select
    i.id, i.establishment_id, i.email, i.matiere, i.classes,
    i.expires_at, i.accepted_at
  into
    _v_inv_id, _v_inv_establishment_id, _v_inv_email, _v_inv_matiere,
    _v_inv_classes, _v_inv_expires_at, _v_inv_accepted_at
  from public.establishment_invitations i
  where i.token = p_token;

  if _v_inv_id is null then
    raise exception 'Invitation introuvable.';
  end if;
  if _v_inv_expires_at < now() then
    raise exception 'Invitation expirée (>48h).';
  end if;
  if _v_inv_accepted_at is not null then
    raise exception 'Invitation déjà acceptée.';
  end if;

  if lower(trim(_v_inv_email)) != lower(trim(_v_user_email)) then
    raise exception
      'Cette invitation a été envoyée à %, vous êtes connecté avec %.',
      _v_inv_email, _v_user_email;
  end if;

  -- Insert / update du membre teacher (idempotent)
  insert into public.establishment_members as em (
    establishment_id, user_id, role, matiere, classes, is_active
  ) values (
    _v_inv_establishment_id,
    _v_user_id,
    'teacher',
    _v_inv_matiere,
    coalesce(_v_inv_classes, array[]::text[]),
    true
  )
  on conflict (establishment_id, user_id) do update
    set role = 'teacher',
        matiere = excluded.matiere,
        classes = excluded.classes,
        is_active = true
  returning em.id into _v_member_id;

  -- Marque l'invitation acceptée
  update public.establishment_invitations
  set accepted_at = now(), accepted_by = _v_user_id
  where id = _v_inv_id;

  -- Récupère le nom de l'école pour le retour
  select e.name into _v_estab_name
  from public.establishments e
  where e.id = _v_inv_establishment_id;

  -- Retourne les infos sans ambiguïté
  out_establishment_id := _v_inv_establishment_id;
  out_establishment_name := _v_estab_name;
  out_member_id := _v_member_id;
  out_role := 'teacher';
  return next;
end;
$$;

grant execute on function public.accept_invitation_rpc(text) to authenticated;
