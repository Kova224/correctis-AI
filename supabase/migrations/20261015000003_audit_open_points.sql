-- =============================================================================
-- Points ouverts de l'audit du 15/10/2026 — corrections avant production
--
--   O2. Copies d'élèves : bucket « copies » privé (liens signés à durée
--       limitée côté app et côté grade-copy).
--   O3. Pack Découverte : accordé seulement après confirmation de l'e-mail
--       (empêche de cumuler 3 copies gratuites par compte jetable).
--   O4. Génération IA du corrigé (option C) : journal des générations pour
--       plafonner l'usage (5 par examen et par 24 h).
--   O5. Notes figées : une copie publiée au casier depuis plus de 3 jours
--       (locked_at dépassé) ne peut plus être modifiée par le prof.
--   O7. Statut d'une commande lisible par son acheteur (paiement refusé
--       détecté par l'app au lieu d'attendre le délai).
--
-- Idempotente.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- O2. Bucket « copies » privé
-- ─────────────────────────────────────────────────────────────────────────────
-- Les URL déjà enregistrées (format /object/public/copies/...) restent en
-- base : l'app et grade-copy en extraient le chemin et demandent un lien
-- signé. Chaque prof garde l'accès à son dossier via la policy
-- « Users manage own copy files » (nécessaire pour createSignedUrl).
update storage.buckets set public = false where id = 'copies';


-- ─────────────────────────────────────────────────────────────────────────────
-- O3. Découverte seulement après confirmation de l'e-mail
-- ─────────────────────────────────────────────────────────────────────────────
-- Fonction interne : accorde les 3 crédits Découverte une seule fois.
create or replace function public.grant_discovery_internal(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_used boolean;
  _v_lot_id uuid;
begin
  select coalesce(discovery_used, false) into _v_used
  from public.profiles where id = p_user_id
  for update;
  if _v_used is null or _v_used then return false; end if;

  insert into public.credit_lots (
    owner_kind, owner_user_id, source, pack_code,
    credits_total, credits_remaining, purchased_at, expires_at, status
  ) values (
    'user', p_user_id, 'discovery', 'discovery',
    3, 3, now(), now() + interval '30 days', 'active'
  ) returning id into _v_lot_id;

  update public.profiles set discovery_used = true where id = p_user_id;

  insert into public.credit_transactions
    (lot_id, user_id, txn_type, delta, reason, settled)
  values (_v_lot_id, p_user_id, 'grant', 3, 'discovery', true);
  return true;
end;
$$;
revoke execute on function public.grant_discovery_internal(uuid) from public, anon, authenticated;

-- À la création du profil : on n'accorde plus d'office. Si l'e-mail est déjà
-- confirmé (Google, ou confirmation désactivée), on accorde après l'insert.
create or replace function public.auto_grant_discovery_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- BEFORE INSERT : rien à faire, l'attribution se fait AFTER INSERT.
  return new;
end;
$$;

create or replace function public.grant_discovery_after_profile_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from auth.users u
     where u.id = new.id and u.email_confirmed_at is not null
  ) then
    perform public.grant_discovery_internal(new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_grant_discovery_after_insert on public.profiles;
create trigger profiles_grant_discovery_after_insert
  after insert on public.profiles
  for each row execute function public.grant_discovery_after_profile_insert();

-- Confirmation de l'e-mail (lien cliqué) → Découverte accordée.
create or replace function public.grant_discovery_on_email_confirmed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    perform public.grant_discovery_internal(new.id);
  end if;
  return new;
end;
$$;
drop trigger if exists on_auth_user_email_confirmed on auth.users;
create trigger on_auth_user_email_confirmed
  after update of email_confirmed_at on auth.users
  for each row execute function public.grant_discovery_on_email_confirmed();

-- RPC appelée par l'app : refuse tant que l'e-mail n'est pas confirmé.
create or replace function public.grant_discovery_credits()
returns table (
  out_lot_id uuid,
  out_credits int,
  out_expires_at timestamptz,
  out_already_used boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_granted boolean;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if not exists (
    select 1 from auth.users where id = _v_user_id and email_confirmed_at is not null
  ) then
    out_already_used := true; out_credits := 0;
    return next; return;
  end if;
  _v_granted := public.grant_discovery_internal(_v_user_id);
  if not _v_granted then
    out_already_used := true; out_credits := 0;
    return next; return;
  end if;
  select id, credits_total, expires_at into out_lot_id, out_credits, out_expires_at
  from public.credit_lots
  where owner_kind = 'user' and owner_user_id = _v_user_id and source = 'discovery'
  order by purchased_at desc limit 1;
  out_already_used := false;
  return next;
end;
$$;
grant execute on function public.grant_discovery_credits() to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- O4. Journal des générations IA du corrigé (plafond)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.answer_key_generations (
  id          bigserial primary key,
  exam_id     uuid not null references public.exams(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now()
);
create index if not exists answer_key_generations_exam_idx
  on public.answer_key_generations(exam_id, created_at desc);
alter table public.answer_key_generations enable row level security;
drop policy if exists "answer_key_generations deny" on public.answer_key_generations;
create policy "answer_key_generations deny"
  on public.answer_key_generations for all using (false);


-- ─────────────────────────────────────────────────────────────────────────────
-- O5. Notes figées après verrouillage (publication + 3 jours)
-- ─────────────────────────────────────────────────────────────────────────────
-- Les écritures serveur (service_role, auth.uid() null) restent possibles
-- pour le support. Le prof ne peut plus modifier notes, commentaires ou
-- pages d'une copie verrouillée ; la suppression « douce » (RPC) reste
-- autorisée, elle ne touche pas aux notes.
create or replace function public.guard_locked_copy_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null
     and old.locked_at is not null and old.locked_at < now()
     and (
       new.general_comment is distinct from old.general_comment
       or new.confidence is distinct from old.confidence
       or new.status is distinct from old.status
       or new.page_images is distinct from old.page_images
       or new.student_name is distinct from old.student_name
       or new.student_ref is distinct from old.student_ref
       or new.graded_at is distinct from old.graded_at
       or new.published_at is distinct from old.published_at
     )
  then
    raise exception 'COPY_LOCKED'
      using hint = 'Copie publiée au casier depuis plus de 3 jours : notes figées.';
  end if;
  return new;
end;
$$;
drop trigger if exists student_copies_guard_locked on public.student_copies;
create trigger student_copies_guard_locked
  before update on public.student_copies
  for each row execute function public.guard_locked_copy_update();

create or replace function public.guard_locked_copy_grades()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_copy uuid := coalesce(new.copy_id, old.copy_id);
begin
  if auth.uid() is not null and exists (
    select 1 from public.student_copies
     where id = _v_copy and locked_at is not null and locked_at < now()
  ) then
    raise exception 'COPY_LOCKED'
      using hint = 'Copie publiée au casier depuis plus de 3 jours : notes figées.';
  end if;
  return coalesce(new, old);
end;
$$;
drop trigger if exists question_grades_guard_locked on public.question_grades;
create trigger question_grades_guard_locked
  before insert or update or delete on public.question_grades
  for each row execute function public.guard_locked_copy_grades();


-- ─────────────────────────────────────────────────────────────────────────────
-- O7. Statut de sa propre commande
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_payment_order_status(p_order_id uuid)
returns table (
  out_status text,
  out_failure_reason text,
  out_paid_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select o.status, o.failure_reason, o.paid_at
  from public.payment_orders o
  where o.id = p_order_id
    and o.buyer_user_id = auth.uid();
$$;
revoke execute on function public.get_my_payment_order_status(uuid) from public, anon;
grant execute on function public.get_my_payment_order_status(uuid) to authenticated;


-- Droits : fonctions internes jamais exposées à l'app
revoke execute on function public.grant_discovery_after_profile_insert() from public, anon, authenticated;
revoke execute on function public.grant_discovery_on_email_confirmed() from public, anon, authenticated;
revoke execute on function public.guard_locked_copy_update() from public, anon, authenticated;
revoke execute on function public.guard_locked_copy_grades() from public, anon, authenticated;
