-- =============================================================================
-- Lookup public d'une invitation par son token (pour pré-remplir l'email)
-- =============================================================================
-- Quand un enseignant clique sur le lien d'invitation `correctis://invite?token=...`
-- on doit pouvoir afficher "Cette invitation a été envoyée à X@y.com" et
-- pré-remplir le RegisterScreen avec cet email — AVANT que l'enseignant ne
-- se soit authentifié.
--
-- On expose UNIQUEMENT l'email + le nom de l'école, jamais la liste des
-- invitations ni les autres champs.
-- Le token étant un secret de 48 caractères, ce SELECT public n'est pas
-- une fuite tant qu'on ne brute-force pas le token.
-- =============================================================================

create or replace function public.get_invitation_info(p_token text)
returns table (
  email text,
  matiere text,
  establishment_name text,
  expired boolean,
  accepted boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    i.email,
    i.matiere,
    e.name as establishment_name,
    (i.expires_at < now()) as expired,
    (i.accepted_at is not null) as accepted
  from public.establishment_invitations i
  join public.establishments e on e.id = i.establishment_id
  where i.token = p_token;
$$;

-- Accessible à tout client (anon ou authentifié) — la sécurité repose sur
-- la complexité du token.
grant execute on function public.get_invitation_info(text) to anon, authenticated;
