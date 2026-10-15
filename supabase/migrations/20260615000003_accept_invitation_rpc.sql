-- =============================================================================
-- RPC accept_invitation_rpc : bypass RLS pour créer la liaison teacher
-- =============================================================================
-- Bug observé : quand un prof clique le lien d'invitation et accepte,
-- aucune ligne n'apparaît dans `establishment_members` (l'INSERT échoue
-- silencieusement à cause des RLS qui dépendent d'auth.uid()). Conséquence :
-- le prof reste "solo" et n'est pas lié à l'admin.
--
-- Cette RPC fait toute la séquence côté serveur en SECURITY DEFINER :
--   1. Vérifie que le token est valide (existe, pas expiré, pas accepté)
--   2. Vérifie que l'email du caller correspond à celui de l'invitation
--   3. Insère le membre teacher
--   4. Marque l'invitation comme acceptée
-- =============================================================================

create or replace function public.accept_invitation_rpc(p_token text)
returns table (
  establishment_id uuid,
  establishment_name text,
  member_id uuid,
  role text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_user_email text;
  v_invitation record;
  v_member_id uuid;
begin
  -- 1. Vérifie que l'user est connecté
  if v_user_id is null then
    raise exception 'Vous devez être connecté pour accepter l''invitation.';
  end if;

  -- 2. Récupère son email
  select email into v_user_email from auth.users where id = v_user_id;
  if v_user_email is null then
    raise exception 'Session invalide.';
  end if;

  -- 3. Lit l'invitation
  select * into v_invitation
  from public.establishment_invitations
  where token = p_token;

  if v_invitation is null then
    raise exception 'Invitation introuvable.';
  end if;
  if v_invitation.expires_at < now() then
    raise exception 'Invitation expirée (>48h).';
  end if;
  if v_invitation.accepted_at is not null then
    raise exception 'Invitation déjà acceptée.';
  end if;

  -- 4. Vérifie email
  if lower(trim(v_invitation.email)) != lower(trim(v_user_email)) then
    raise exception 'Cette invitation a été envoyée à %, vous êtes connecté avec %.',
      v_invitation.email, v_user_email;
  end if;

  -- 5. Insère ou update le membre teacher (idempotent via upsert)
  insert into public.establishment_members (
    establishment_id, user_id, role, matiere, classes, is_active
  ) values (
    v_invitation.establishment_id,
    v_user_id,
    'teacher',
    v_invitation.matiere,
    coalesce(v_invitation.classes, array[]::text[]),
    true
  )
  on conflict (establishment_id, user_id) do update
    set role = 'teacher',
        matiere = excluded.matiere,
        classes = excluded.classes,
        is_active = true
  returning id into v_member_id;

  -- 6. Marque l'invitation acceptée
  update public.establishment_invitations
  set accepted_at = now(), accepted_by = v_user_id
  where id = v_invitation.id;

  -- 7. Retourne les infos
  return query
  select
    v_invitation.establishment_id,
    (select name from public.establishments where id = v_invitation.establishment_id),
    v_member_id,
    'teacher'::text;
end;
$$;

grant execute on function public.accept_invitation_rpc(text) to authenticated;
