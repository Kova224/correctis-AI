-- =============================================================================
-- Michel : « infinite recursion detected in policy for relation
-- establishment_members » quand l'admin crée son école.
--
-- Cause : le insert+select depuis Flutter passe par les policies RLS sur
-- `establishments` qui checkent `establishment_members`, dont les propres
-- policies re-checkent `establishments` → boucle infinie.
--
-- Fix : RPC SECURITY DEFINER qui insère l'école + le membership admin
-- en un seul passage, en bypassant les RLS.
-- =============================================================================

create or replace function public.admin_create_my_establishment(
  p_name text,
  p_city text default null,
  p_plan text default 'trial'
)
returns table (
  out_id uuid,
  out_name text,
  out_city text,
  out_plan text,
  out_status text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  p_name := trim(p_name);
  if p_name = '' then raise exception 'Nom d''école requis.'; end if;

  -- Empêche un user qui est déjà admin d'une école d'en créer une seconde
  if exists (
    select 1 from public.establishment_members
     where user_id = _v_user_id
       and role = 'admin'
       and is_active = true
  ) then
    raise exception 'Vous administrez déjà une école.';
  end if;

  insert into public.establishments (name, city, plan, status, owner_id)
  values (p_name, nullif(trim(coalesce(p_city, '')), ''),
          p_plan, 'active', _v_user_id)
  returning id into _v_estab_id;

  -- Le trigger on_establishment_created crée déjà la row admin,
  -- mais on force au cas où (idempotent grâce à on conflict).
  insert into public.establishment_members
    (establishment_id, user_id, role, is_active)
  values (_v_estab_id, _v_user_id, 'admin', true)
  on conflict (establishment_id, user_id) do update
    set role = 'admin', is_active = true;

  return query
  select e.id, e.name, e.city, e.plan, e.status
  from public.establishments e
  where e.id = _v_estab_id;
end;
$$;

grant execute on function public.admin_create_my_establishment(text, text, text)
  to authenticated;
