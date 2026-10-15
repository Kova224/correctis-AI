-- =============================================================================
-- Suppression de compte (exigence Google Play) — règles validées le 15/10/2026
--
--   • Demande depuis l'app (ou par e-mail au support) → suppression
--     définitive après 30 jours. Le compte peut annuler pendant ce délai.
--   • Paiements : conservés pour la comptabilité, mais anonymisés (plus de
--     lien vers le compte, plus de payload CinetPay).
--   • Prof rattaché à une école : ses examens et ses notes restent à l'école
--     (photos des copies et du sujet effacées).
--   • Prof solo : tous ses examens, copies et notes sont supprimés.
--   • Crédits personnels non utilisés : perdus.
--   • Propriétaire d'une école, ou seul admin actif d'une école : bloqué
--     (il doit d'abord passer par le support).
--   • Photos (copies, sujets, avatar) : effacées dans tous les cas — par
--     l'Edge Function delete-account, qui appelle ensuite purge_account_data
--     puis supprime l'utilisateur Auth.
--
-- Idempotente.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Colonnes de suivi sur le profil
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists deletion_requested_at timestamptz,
  add column if not exists deletion_scheduled_for timestamptz;

create index if not exists profiles_deletion_due_idx
  on public.profiles(deletion_scheduled_for)
  where deletion_scheduled_for is not null;
-- Pas de grant UPDATE : seules les RPC ci-dessous modifient ces colonnes
-- (le prof n'a le droit d'écrire que display_name, email, phone, school,
-- photo_path — cf. migration 20261015000002).


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Clés étrangères : ce qui doit survivre à la suppression de l'utilisateur
-- ─────────────────────────────────────────────────────────────────────────────

-- 2a. Examens : plus de cascade depuis auth.users. Les examens d'école
-- gardent l'identifiant de l'ancien prof (le casier admin continue à les
-- regrouper par enseignant, avec le libellé « Enseignant ») ; les examens
-- solo sont supprimés explicitement par purge_account_data.
alter table public.exams drop constraint if exists exams_owner_id_fkey;

-- 2b. Paiements : conservés et détachés du compte.
alter table public.payment_orders alter column buyer_user_id drop not null;
alter table public.payment_orders drop constraint if exists payment_orders_buyer_user_id_fkey;
alter table public.payment_orders
  add constraint payment_orders_buyer_user_id_fkey
  foreign key (buyer_user_id) references auth.users(id) on delete set null;
alter table public.payment_orders drop constraint if exists payment_orders_target_user_id_fkey;
alter table public.payment_orders
  add constraint payment_orders_target_user_id_fkey
  foreign key (target_user_id) references auth.users(id) on delete set null;
-- Un achat « user » peut désormais avoir perdu son destinataire.
alter table public.payment_orders drop constraint if exists payment_target_consistent;
alter table public.payment_orders
  add constraint payment_target_consistent check (
    (target_kind = 'user' and target_establishment_id is null)
    or (target_kind = 'establishment' and target_establishment_id is not null)
  );

-- 2c. Transactions de crédits : l'historique de consommation d'une école
-- reste complet même si le prof qui a corrigé disparaît.
alter table public.credit_transactions drop constraint if exists credit_transactions_user_id_fkey;
alter table public.credit_transactions
  add constraint credit_transactions_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete set null;

-- 2d. Invitations et créneaux créés par un admin : on garde la ligne.
alter table public.establishment_invitations alter column invited_by drop not null;
alter table public.establishment_invitations drop constraint if exists establishment_invitations_invited_by_fkey;
alter table public.establishment_invitations
  add constraint establishment_invitations_invited_by_fkey
  foreign key (invited_by) references auth.users(id) on delete set null;
alter table public.establishment_invitations drop constraint if exists establishment_invitations_accepted_by_fkey;
alter table public.establishment_invitations
  add constraint establishment_invitations_accepted_by_fkey
  foreign key (accepted_by) references auth.users(id) on delete set null;

alter table public.establishment_teacher_slots alter column created_by drop not null;
alter table public.establishment_teacher_slots drop constraint if exists establishment_teacher_slots_created_by_fkey;
alter table public.establishment_teacher_slots
  add constraint establishment_teacher_slots_created_by_fkey
  foreign key (created_by) references auth.users(id) on delete set null;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Règle de blocage (propriétaire ou seul admin d'une école)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.account_deletion_blocker(p_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.establishments where owner_id = p_user_id) then
    return 'SCHOOL_OWNER';
  end if;
  if exists (
    select 1 from public.establishment_members m
     where m.user_id = p_user_id and m.role = 'admin' and m.is_active
       and not exists (
         select 1 from public.establishment_members o
          where o.establishment_id = m.establishment_id
            and o.role = 'admin' and o.is_active
            and o.user_id <> p_user_id
       )
  ) then
    return 'SOLE_ADMIN';
  end if;
  return null;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RPC de l'app
-- ─────────────────────────────────────────────────────────────────────────────

-- État de la suppression pour le compte connecté.
create or replace function public.get_my_account_deletion()
returns table (
  out_requested_at timestamptz,
  out_scheduled_for timestamptz,
  out_blocker text,
  out_in_school boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  _v_uid uuid := auth.uid();
begin
  if _v_uid is null then raise exception 'Non authentifié.'; end if;
  return query
  select p.deletion_requested_at,
         p.deletion_scheduled_for,
         public.account_deletion_blocker(_v_uid),
         exists (select 1 from public.exams e
                  where e.owner_id = _v_uid and e.establishment_id is not null)
  from public.profiles p
  where p.id = _v_uid;
end;
$$;

-- Demande de suppression (délai de 30 jours). Idempotente : une seconde
-- demande renvoie la date déjà prévue.
create or replace function public.request_account_deletion()
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_uid uuid := auth.uid();
  _v_blocker text;
  _v_when timestamptz;
begin
  if _v_uid is null then raise exception 'Non authentifié.'; end if;
  _v_blocker := public.account_deletion_blocker(_v_uid);
  if _v_blocker is not null then
    raise exception '%', _v_blocker
      using hint = 'Propriétaire ou seul administrateur d''une école : contactez le support.';
  end if;

  select deletion_scheduled_for into _v_when
  from public.profiles where id = _v_uid for update;
  if _v_when is not null then return _v_when; end if;

  update public.profiles
     set deletion_requested_at = now(),
         deletion_scheduled_for = now() + interval '30 days'
   where id = _v_uid
  returning deletion_scheduled_for into _v_when;
  return _v_when;
end;
$$;

-- Annulation pendant le délai.
create or replace function public.cancel_account_deletion()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_uid uuid := auth.uid();
begin
  if _v_uid is null then raise exception 'Non authentifié.'; end if;
  update public.profiles
     set deletion_requested_at = null,
         deletion_scheduled_for = null
   where id = _v_uid and deletion_scheduled_for is not null;
  return found;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Fonctions serveur (service_role uniquement)
-- ─────────────────────────────────────────────────────────────────────────────

-- Demande reçue par e-mail (page web / support) : à lancer depuis le SQL
-- Editor ou avec la clé service. p_days = 0 → suppression au prochain passage
-- du job quotidien.
create or replace function public.admin_request_account_deletion(
  p_email text,
  p_days int default 30
)
returns table (out_user_id uuid, out_scheduled_for timestamptz, out_blocker text)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_uid uuid;
begin
  select id into _v_uid from auth.users where lower(email) = lower(trim(p_email));
  if _v_uid is null then raise exception 'USER_NOT_FOUND'; end if;
  out_user_id := _v_uid;
  out_blocker := public.account_deletion_blocker(_v_uid);
  if out_blocker is null then
    update public.profiles
       set deletion_requested_at = coalesce(deletion_requested_at, now()),
           deletion_scheduled_for = now() + make_interval(days => greatest(p_days, 0))
     where id = _v_uid
    returning deletion_scheduled_for into out_scheduled_for;
  end if;
  return next;
end;
$$;

-- Comptes dont le délai est écoulé.
create or replace function public.list_due_account_deletions(p_limit int default 50)
returns table (out_user_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select p.id from public.profiles p
  where p.deletion_scheduled_for is not null
    and p.deletion_scheduled_for <= now()
  order by p.deletion_scheduled_for
  limit greatest(p_limit, 1);
$$;

-- Fichiers du compte dans le stockage (tous les buckets rangent par
-- « <user_id>/... »). La suppression elle-même passe par l'API Storage.
create or replace function public.list_user_storage_objects(p_user_id uuid)
returns table (out_bucket text, out_name text)
language sql
stable
security definer
set search_path = public, storage
as $$
  select o.bucket_id, o.name
  from storage.objects o
  where o.bucket_id in ('copies', 'subjects', 'avatars')
    and o.name like p_user_id::text || '/%';
$$;

-- Purge des données en base. Appelée par delete-account APRÈS l'effacement
-- des fichiers et AVANT la suppression de l'utilisateur Auth (qui fait
-- disparaître en cascade le profil, les adhésions, les quotas, les lots de
-- crédits personnels, etc.).
create or replace function public.purge_account_data(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_blocker text;
  _v_payments int;
  _v_solo_exams int;
  _v_school_exams int;
begin
  _v_blocker := public.account_deletion_blocker(p_user_id);
  if _v_blocker is not null then
    return jsonb_build_object('ok', false, 'blocker', _v_blocker);
  end if;

  -- Paiements : on garde montant, devise, pays, opérateur, statut, dates et
  -- références CinetPay ; on retire tout ce qui peut contenir des données
  -- personnelles. Le lien vers le compte tombe avec la suppression Auth.
  update public.payment_orders
     set cinetpay_payload = null,
         cinetpay_payment_url = null,
         cinetpay_payment_token = null,
         cinetpay_notify_token = null
   where buyer_user_id = p_user_id or target_user_id = p_user_id;
  get diagnostics _v_payments = row_count;

  -- Examens solo : tout part (questions, copies, notes en cascade).
  delete from public.exams
   where owner_id = p_user_id and establishment_id is null;
  get diagnostics _v_solo_exams = row_count;

  -- Examens d'école : restent à l'école, sans les photos.
  update public.exams
     set subject_images = '{}'
   where owner_id = p_user_id and establishment_id is not null;
  get diagnostics _v_school_exams = row_count;

  update public.student_copies c
     set page_images = '{}'
    from public.exams e
   where e.id = c.exam_id
     and e.owner_id = p_user_id
     and e.establishment_id is not null
     and c.page_images <> '{}';

  return jsonb_build_object(
    'ok', true,
    'payments_anonymized', _v_payments,
    'solo_exams_deleted', _v_solo_exams,
    'school_exams_kept', _v_school_exams
  );
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Droits
-- ─────────────────────────────────────────────────────────────────────────────
revoke execute on function public.account_deletion_blocker(uuid) from public, anon, authenticated;
revoke execute on function public.get_my_account_deletion() from public, anon;
revoke execute on function public.request_account_deletion() from public, anon;
revoke execute on function public.cancel_account_deletion() from public, anon;
grant execute on function public.get_my_account_deletion() to authenticated;
grant execute on function public.request_account_deletion() to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;

revoke execute on function public.admin_request_account_deletion(text, int) from public, anon, authenticated;
revoke execute on function public.list_due_account_deletions(int) from public, anon, authenticated;
revoke execute on function public.list_user_storage_objects(uuid) from public, anon, authenticated;
revoke execute on function public.purge_account_data(uuid) from public, anon, authenticated;
grant execute on function public.account_deletion_blocker(uuid) to service_role;
grant execute on function public.admin_request_account_deletion(text, int) to service_role;
grant execute on function public.list_due_account_deletions(int) to service_role;
grant execute on function public.list_user_storage_objects(uuid) to service_role;
grant execute on function public.purge_account_data(uuid) to service_role;
