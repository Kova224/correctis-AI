-- =============================================================================
-- CORRECTIS — Durcissement de sécurité
-- Corrige les avertissements du Supabase Database Linter :
--   - Function Search Path Mutable
--   - Public Bucket Allows Listing
--   - Public Can Execute SECURITY DEFINER Function
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. set_updated_at : ajoute SET search_path et passe en SECURITY INVOKER
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. handle_new_user : reste SECURITY DEFINER (nécessaire pour bypass RLS lors
--    de la création du profil), mais on REVOQUE l'EXECUTE aux rôles publics.
--    Seul le trigger pourra l'appeler — pas accessible via /rest/v1/rpc/.
-- -----------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'displayName', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public;
revoke execute on function public.handle_new_user() from anon;
revoke execute on function public.handle_new_user() from authenticated;
-- Le rôle "postgres" (super-admin) garde EXECUTE pour que le trigger fonctionne.

-- -----------------------------------------------------------------------------
-- 3. rls_auto_enable (fonction Supabase interne, parfois installée automatiquement)
--    On la verrouille au cas où elle existe.
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on p.pronamespace = n.oid
    where n.nspname = 'public' and p.proname = 'rls_auto_enable'
  ) then
    execute 'revoke execute on function public.rls_auto_enable() from public, anon, authenticated';
  end if;
end$$;

-- -----------------------------------------------------------------------------
-- 4. Bucket avatars : retire la policy SELECT trop large.
--    Les URLs publiques (`getPublicUrl`) fonctionnent sans cette policy.
-- -----------------------------------------------------------------------------
drop policy if exists "Avatars are publicly readable" on storage.objects;

-- -----------------------------------------------------------------------------
-- Note : le warning "auth_leaked_password_protection" se règle dans le dashboard
-- Authentication → Policies → Password Protection → "Check against HaveIBeenPwned"
-- Ce n'est pas configurable en SQL.
-- =============================================================================
