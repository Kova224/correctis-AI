-- =============================================================================
-- B2 (Sprint 2) — Suppression de note par le prof : règle 3 jours
--
-- CONTEXTE (retour Michel) :
-- "Dans le compte établissement quand un prof efface une note ça s'efface
--  directement dans le casier alors que ça doit rester dans le casier si et
--  seulement si la note a déjà passé 3 jours dans le casier."
--
-- LOGIQUE ATTENDUE :
--   - Si note publiée depuis < 3 jours → suppression physique OK
--     (retirée de la vue prof ET du casier admin)
--   - Si note publiée depuis >= 3 jours → soft delete :
--     retirée de la vue prof, MAIS reste dans le casier admin
--   - Copie non publiée → suppression physique (comportement inchangé)
--
-- MÉCANIQUE :
--   1. Nouvelle colonne `deleted_by_prof_at` sur student_copies
--   2. `delete_copy_safe` refactorée avec soft delete conditionnel
--   3. Les RPCs du casier admin (get_school_casier_notes etc.) restent
--      inchangées — elles filtrent sur published_at is not null,
--      les copies soft-deleted apparaissent toujours car published_at reste
--   4. La lecture prof (exam_service côté Flutter) doit filtrer
--      deleted_by_prof_at is null → géré côté client via un update
-- =============================================================================

-- 1. Ajout de la colonne soft-delete
alter table public.student_copies
  add column if not exists deleted_by_prof_at timestamptz;

comment on column public.student_copies.deleted_by_prof_at is
  'Timestamp de soft-delete par le prof. Non-null = copie masquée pour le prof '
  'mais toujours visible dans le casier admin (car locked_at atteint).';

-- 2. Nouvelle version de delete_copy_safe avec soft delete conditionnel
create or replace function public.delete_copy_safe(p_copy_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_exam_id uuid;
  _v_locked_at timestamptz;
  _v_published_at timestamptz;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;

  select c.exam_id, c.locked_at, c.published_at
    into _v_exam_id, _v_locked_at, _v_published_at
  from public.student_copies c
  where c.id = p_copy_id;

  if _v_exam_id is null then
    raise exception 'Copie introuvable.';
  end if;

  -- Vérifie propriété
  if not exists (
    select 1 from public.exams
    where id = _v_exam_id and owner_id = _v_user_id
  ) then
    raise exception 'Vous n''êtes pas propriétaire de cet examen.';
  end if;

  -- CAS 1 : copie non publiée OU publiée depuis < 3 jours
  --         → suppression PHYSIQUE (retire de partout)
  if _v_published_at is null
     or _v_locked_at is null
     or _v_locked_at >= now() then
    delete from public.student_copies where id = p_copy_id;
    return 'DELETED';
  end if;

  -- CAS 2 : copie publiée depuis >= 3 jours (locked_at < now())
  --         → soft delete : retire de la vue prof, garde dans casier admin
  update public.student_copies
    set deleted_by_prof_at = now()
    where id = p_copy_id;
  return 'ARCHIVED';
end;
$$;

grant execute on function public.delete_copy_safe(uuid) to authenticated;

-- 3. Vue "student_copies_active" pour la lecture prof (filtre soft-deleted).
-- On garde la table telle quelle mais on expose une vue pratique pour Flutter.
-- Note : Flutter continue à lire la table + filtre côté client (backward compat).
create or replace view public.student_copies_active as
  select * from public.student_copies
  where deleted_by_prof_at is null;

grant select on public.student_copies_active to authenticated;
