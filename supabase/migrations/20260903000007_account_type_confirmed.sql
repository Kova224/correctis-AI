-- =============================================================================
-- Michel : Google Sign-In créait des comptes 'teacher' par défaut car il n'y
-- avait pas de choix. On introduit un flag `account_type_confirmed` :
--   - false → l'app affiche le picker "Enseignant / Administrateur" au
--     prochain login et update account_type
--   - true → routing normal selon account_type
--
-- Backfill : tous les users existants sont considérés confirmés (ils ont
-- soit choisi via le register form, soit sont là depuis longtemps).
-- =============================================================================

alter table public.profiles
  add column if not exists account_type_confirmed boolean not null default false;

-- Backfill users existants
update public.profiles
   set account_type_confirmed = true
 where account_type_confirmed = false;

-- Trigger handle_new_user : si l'utilisateur passe par register (accountType
-- présent dans metadata), on marque déjà confirmé. Sinon (Google Sign-In,
-- OAuth futur…) on laisse false → picker au 1er login.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_meta_type text := new.raw_user_meta_data->>'accountType';
  _v_confirmed boolean := _v_meta_type is not null;
begin
  insert into public.profiles (
    id, email, display_name, account_type, account_type_confirmed
  )
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'displayName', ''),
    case
      when _v_meta_type = 'admin' then 'admin'
      else 'teacher'
    end,
    _v_confirmed
  )
  on conflict (id) do update
    set email = excluded.email,
        display_name = case
          when excluded.display_name <> '' then excluded.display_name
          else profiles.display_name
        end;
  return new;
end;
$$;

-- RPC pour que le client marque son type de compte confirmé.
create or replace function public.confirm_my_account_type(p_account_type text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if p_account_type not in ('teacher', 'admin') then
    raise exception 'Type de compte invalide.';
  end if;
  update public.profiles
     set account_type = p_account_type,
         account_type_confirmed = true
   where id = _v_user_id;
end;
$$;

grant execute on function public.confirm_my_account_type(text) to authenticated;
