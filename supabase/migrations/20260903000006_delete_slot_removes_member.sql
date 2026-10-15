-- =============================================================================
-- Michel : « quand on supprime un prof il doit totalement disparaître de la
-- liste (mais ses notes restent dans le casier) ».
--
-- Bug : admin_delete_teacher_slot faisait juste `is_active = false` sur la
-- row establishment_members → le prof restait affiché en "SUSPENDU".
--
-- Fix : la suppression du slot supprime aussi complètement la membership
-- ET le quota (crédits engagés libérés → reviennent dans le pool dispo).
-- Les copies/notes du casier restent visibles car exam.owner_id pointe
-- vers auth.users (le user persiste, seule sa membership dans cette école
-- disparaît).
-- =============================================================================

create or replace function public.admin_delete_teacher_slot(p_slot_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
  _v_target_user_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;

  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then raise exception 'Réservé admin.'; end if;

  -- Récupère le user_id du prof s'il avait déjà rejoint (claimed)
  select claimed_by_user_id into _v_target_user_id
  from public.establishment_teacher_slots
  where id = p_slot_id and establishment_id = _v_estab_id;

  -- Supprime le slot en premier (contrainte unique school_email libérée)
  delete from public.establishment_teacher_slots
  where id = p_slot_id and establishment_id = _v_estab_id;

  -- Si le prof avait rejoint, on retire aussi sa membership + son quota.
  -- Ses copies/notes restent (exam.owner_id reste attaché au user_id global).
  if _v_target_user_id is not null then
    delete from public.establishment_members
    where establishment_id = _v_estab_id
      and user_id = _v_target_user_id;

    delete from public.teacher_quotas
    where establishment_id = _v_estab_id
      and user_id = _v_target_user_id;
  end if;
end;
$$;

grant execute on function public.admin_delete_teacher_slot(uuid) to authenticated;
