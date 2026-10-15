-- =============================================================================
-- Michel (spec §3, §8-3) : étanchéité stricte des rôles au niveau du COMPTE.
-- Un compte est soit prof (peut être solo ou rejoindre des écoles) soit
-- admin (gère UNE école, jamais d'écrans de correction).
--
-- Change 1 : ajoute profiles.account_type ('teacher' | 'admin').
-- Change 2 : backfill — les users déjà admin dans establishment_members
--            deviennent 'admin' au niveau compte.
-- Change 3 : trigger handle_new_user lit accountType depuis raw_user_meta_data.
-- =============================================================================

alter table public.profiles
  add column if not exists account_type text not null default 'teacher';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_account_type_check'
  ) then
    alter table public.profiles
      add constraint profiles_account_type_check
      check (account_type in ('teacher', 'admin'));
  end if;
end $$;

-- Backfill : un user qui est admin d'au moins une école devient 'admin'
update public.profiles p
   set account_type = 'admin'
 where account_type = 'teacher'
   and exists (
     select 1 from public.establishment_members m
      where m.user_id = p.id
        and m.role = 'admin'
        and m.is_active = true
   );

-- Trigger : accepte accountType via metadata au signup
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name, account_type)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'displayName', ''),
    case
      when coalesce(new.raw_user_meta_data->>'accountType', 'teacher') = 'admin'
        then 'admin'
      else 'teacher'
    end
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
