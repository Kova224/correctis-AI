-- =============================================================================
-- Fix : teacher_join_school utilisait public.notifications qui n'existe pas.
-- La bonne table est public.establishment_notifications (schéma différent).
-- On corrige la RPC pour utiliser le bon schéma et éviter le blocage.
-- =============================================================================

create or replace function public.teacher_join_school(
  p_school_email text,
  p_join_code text
)
returns table (
  out_ok boolean,
  out_reason text,
  out_establishment_id uuid,
  out_establishment_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_slot record;
  _v_estab record;
  _v_admin_ids uuid[];
begin
  if _v_user_id is null then
    out_ok := false; out_reason := 'NOT_AUTHENTICATED';
    return next; return;
  end if;

  p_school_email := lower(trim(p_school_email));
  p_join_code := upper(trim(p_join_code));

  select * into _v_slot
  from public.establishment_teacher_slots
  where school_email = p_school_email and join_code = p_join_code;

  if _v_slot is null then
    out_ok := false; out_reason := 'SLOT_NOT_FOUND';
    return next; return;
  end if;

  if _v_slot.status = 'claimed'
     and _v_slot.claimed_by_user_id != _v_user_id then
    out_ok := false; out_reason := 'ALREADY_CLAIMED_BY_OTHER';
    return next; return;
  end if;

  if _v_slot.status = 'suspended' then
    out_ok := false; out_reason := 'SLOT_SUSPENDED';
    return next; return;
  end if;

  update public.establishment_teacher_slots
    set status = 'claimed',
        claimed_by_user_id = _v_user_id,
        claimed_at = coalesce(claimed_at, now()),
        updated_at = now()
    where id = _v_slot.id;

  insert into public.establishment_members (
    establishment_id, user_id, role, matiere, matieres, is_active
  )
  values (
    _v_slot.establishment_id, _v_user_id, 'teacher',
    coalesce(_v_slot.matieres[1], null),
    coalesce(_v_slot.matieres, '{}'),
    true
  )
  on conflict (establishment_id, user_id)
    do update set
      is_active = true,
      matiere = coalesce(excluded.matiere, establishment_members.matiere),
      matieres = coalesce(excluded.matieres, establishment_members.matieres);

  select id, name into _v_estab
  from public.establishments where id = _v_slot.establishment_id;

  -- Notification admin : best-effort — si la table ou la RPC n'existe pas,
  -- on ne bloque pas le join. Le prof reste correctement rattaché.
  begin
    -- Récupère les user_ids des admins actifs pour cibler la notif
    select array_agg(user_id) into _v_admin_ids
    from public.establishment_members
    where establishment_id = _v_slot.establishment_id
      and role = 'admin'
      and is_active = true;

    if _v_admin_ids is not null and array_length(_v_admin_ids, 1) > 0 then
      insert into public.establishment_notifications (
        establishment_id, author_user_id, title, body, targets
      )
      values (
        _v_slot.establishment_id,
        _v_user_id,
        'Nouvel enseignant rejoint',
        _v_slot.teacher_name || ' a rejoint votre école via le code ' ||
          _v_slot.join_code || '.',
        _v_admin_ids
      );
    end if;
  exception when others then
    -- Log via NOTICE mais on continue — le join est le comportement critique,
    -- pas la notification.
    raise notice 'Notification admin ignorée : %', SQLERRM;
  end;

  out_ok := true;
  out_reason := 'OK';
  out_establishment_id := _v_estab.id;
  out_establishment_name := _v_estab.name;
  return next;
end;
$$;

grant execute on function public.teacher_join_school(text, text) to authenticated;
