-- =============================================================================
-- Durcissement sécurité — audit du 15/10/2026 (avant mise en prod grille v5)
--
-- Corrige les failles trouvées pendant l'audit :
--   A1. Crédits gratuits illimités : un utilisateur pouvait remettre
--       profiles.discovery_used à false (UPDATE direct autorisé par la RLS)
--       puis rappeler grant_discovery_credits() → +3 crédits à l'infini.
--       Idem pour account_type / account_type_confirmed / billing_country.
--       → seules les colonnes « profil » restent modifiables par l'app.
--   A2. N'importe quel compte pouvait s'insérer comme enseignant actif de
--       n'importe quelle école (policy "Self insert as teacher") sans code
--       ni invitation → voit les membres, apparaît chez l'admin.
--       → l'adhésion passe uniquement par les RPC (invitation / code).
--   A3. Un prof pouvait rattacher son examen à une école dont il n'est pas
--       membre (exams.establishment_id libre) → notes injectées dans le
--       casier officiel d'une autre école.
--   A4. Corrections gratuites : l'Edge Function grade-copy pouvait être
--       appelée directement sans réservation de crédits. Nouvelle RPC
--       authorize_grading() appelée par grade-copy avant tout appel IA
--       (relances HITL gratuites plafonnées à 3 par copie).
--   A5. Remboursement par le prof d'une correction encore en cours
--       (passer la copie en 'error' pendant le traitement) → délai de
--       3 minutes + balayage serveur des débits restés en suspens.
--   A6. Pages ajoutées après une réservation : complément de crédits.
--   A7. Fonctions SECURITY DEFINER exécutables par le rôle anon
--       (clé publique embarquée dans l'app) → réservé aux comptes connectés.
--   A8. Force brute possible sur l'identifiant de rattachement prof
--       (teacher_join_school) → 10 échecs max par heure et par compte.
--   A9. Listing public des buckets copies/subjects (copies d'élèves) → retiré.
--
-- Idempotente.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- A1. Colonnes protégées sur profiles
-- ─────────────────────────────────────────────────────────────────────────────
-- Les profils sont créés par le trigger handle_new_user (SECURITY DEFINER) ;
-- les champs sensibles ne changent que via des RPC SECURITY DEFINER
-- (confirm_my_account_type, set_my_billing_country, grant_discovery_credits).
revoke insert, update on public.profiles from anon, authenticated;
grant update (display_name, email, phone, school, photo_path)
  on public.profiles to authenticated;

-- Le type de compte ne peut être confirmé qu'une seule fois par l'utilisateur
-- (évite de basculer prof ↔ admin à volonté après l'inscription).
create or replace function public.confirm_my_account_type(p_account_type text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_confirmed boolean;
  _v_current text;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if p_account_type not in ('teacher', 'admin') then
    raise exception 'Type de compte invalide.';
  end if;
  select account_type_confirmed, account_type
    into _v_confirmed, _v_current
  from public.profiles where id = _v_user_id;
  if coalesce(_v_confirmed, false) and _v_current is distinct from p_account_type then
    raise exception 'ACCOUNT_TYPE_LOCKED'
      using hint = 'Le type de compte a déjà été choisi. Contactez le support pour le changer.';
  end if;
  update public.profiles
     set account_type = p_account_type,
         account_type_confirmed = true
   where id = _v_user_id;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- A2. Plus d'auto-inscription directe comme enseignant d'une école
-- ─────────────────────────────────────────────────────────────────────────────
drop policy if exists "Self insert as teacher" on public.establishment_members;


-- ─────────────────────────────────────────────────────────────────────────────
-- A3. Un examen ne peut être rattaché qu'à une école dont le prof est membre
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.check_exam_establishment_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.establishment_id is not null
     and (tg_op = 'INSERT' or new.establishment_id is distinct from old.establishment_id)
     and auth.uid() is not null
     and not exists (
       select 1 from public.establishment_members m
        where m.establishment_id = new.establishment_id
          and m.user_id = new.owner_id
          and m.is_active = true
     )
  then
    raise exception 'NOT_MEMBER_OF_ESTABLISHMENT'
      using hint = 'Vous n''êtes pas enseignant actif de cette école.';
  end if;
  return new;
end;
$$;

drop trigger if exists exams_check_establishment on public.exams;
create trigger exams_check_establishment
  before insert or update of establishment_id on public.exams
  for each row execute function public.check_exam_establishment_membership();


-- ─────────────────────────────────────────────────────────────────────────────
-- A4. Autorisation serveur avant chaque correction IA
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.copy_grading_runs (
  id          uuid primary key default gen_random_uuid(),
  copy_id     uuid not null references public.student_copies(id) on delete cascade,
  kind        text not null check (kind in ('paid','hitl')),
  created_at  timestamptz not null default now()
);
create index if not exists copy_grading_runs_copy_idx on public.copy_grading_runs(copy_id);
alter table public.copy_grading_runs enable row level security;
drop policy if exists "copy_grading_runs deny" on public.copy_grading_runs;
create policy "copy_grading_runs deny" on public.copy_grading_runs for all using (false);

create or replace function public.authorize_grading(
  p_copy_id uuid,
  p_hitl boolean default false
)
returns table (out_ok boolean, out_reason text)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_open int;
  _v_net int;
  _v_hitl_runs int;
begin
  -- 1. Un débit est en cours pour cette copie → correction payée.
  select coalesce(-sum(delta), 0)::int into _v_open
  from public.credit_transactions
  where ref_copy_id = p_copy_id
    and txn_type in ('reserve','consume')
    and settled = false;
  if _v_open > 0 then
    insert into public.copy_grading_runs (copy_id, kind) values (p_copy_id, 'paid');
    out_ok := true; out_reason := 'PAID'; return next; return;
  end if;

  -- 2. Relance Human-in-the-Loop : incluse si la copie a déjà été payée,
  --    plafonnée à 3 relances par copie.
  if p_hitl then
    select coalesce(-sum(delta), 0)::int into _v_net
    from public.credit_transactions
    where ref_copy_id = p_copy_id
      and txn_type in ('reserve','consume','refund');
    select count(*)::int into _v_hitl_runs
    from public.copy_grading_runs
    where copy_id = p_copy_id and kind = 'hitl';
    if _v_net > 0 and _v_hitl_runs < 3 then
      insert into public.copy_grading_runs (copy_id, kind) values (p_copy_id, 'hitl');
      out_ok := true; out_reason := 'HITL_INCLUDED'; return next; return;
    end if;
    if _v_net > 0 then
      out_ok := false; out_reason := 'HITL_LIMIT_REACHED'; return next; return;
    end if;
  end if;

  out_ok := false; out_reason := 'PAYMENT_REQUIRED';
  return next;
end;
$$;
revoke execute on function public.authorize_grading(uuid, boolean) from public, anon, authenticated;
grant execute on function public.authorize_grading(uuid, boolean) to service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- A5 + A6. reserve_credits : complément si pages ajoutées, formats refusés
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.reserve_credits(
  p_copy_id uuid,
  p_establishment_id uuid default null,
  p_hitl boolean default false
)
returns table (
  out_ok boolean,
  out_lot_id uuid,
  out_remaining_after int,
  out_reason text,
  out_credits int,
  out_pages int,
  out_available int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_owner uuid;
  _v_pages int;
  _v_images text[];
  _v_total int;
  _v_needed int;
  _v_open int;
  _v_net int;
  _v_estab uuid;
  _v_quota_limit int;
  _v_quota_used int;
  _v_available int;
  _v_left int;
  _v_take int;
  _v_first_lot uuid;
  _v_lot record;
begin
  out_ok := false; out_credits := 0; out_pages := 0; out_available := 0;

  if _v_user_id is null then
    out_reason := 'NOT_AUTHENTICATED'; return next; return;
  end if;

  select e.owner_id, c.page_images, coalesce(array_length(c.page_images, 1), 0)
    into _v_owner, _v_images, _v_pages
  from public.student_copies c
  join public.exams e on e.id = c.exam_id
  where c.id = p_copy_id;

  if _v_owner is null then
    out_reason := 'COPY_NOT_FOUND'; return next; return;
  end if;
  if _v_owner <> _v_user_id then
    out_reason := 'NOT_OWNER'; return next; return;
  end if;
  out_pages := _v_pages;
  if _v_pages = 0 then
    out_reason := 'NO_PAGES'; return next; return;
  end if;
  -- Un PDF multi-pages compterait pour 1 page : seules les images sont admises.
  if exists (
    select 1 from unnest(_v_images) u
     where lower(u) ~ '\.(pdf|docx?|heic)(\?|$)'
  ) then
    out_reason := 'UNSUPPORTED_PAGE_FORMAT'; return next; return;
  end if;

  _v_total := public.credits_for_pages(_v_pages);

  -- Débit en cours pour cette copie (relance auto, double tap…) : on ne
  -- re-débite pas ; on complète seulement si des pages ont été ajoutées.
  select coalesce(-sum(delta), 0)::int into _v_open
  from public.credit_transactions
  where ref_copy_id = p_copy_id
    and txn_type in ('reserve','consume')
    and settled = false;
  if _v_open >= _v_total then
    out_ok := true; out_reason := 'OK_ALREADY_RESERVED'; out_credits := _v_open;
    return next; return;
  end if;

  -- Relance Human-in-the-Loop : incluse dans les crédits déjà débités.
  if p_hitl and _v_open = 0 then
    select coalesce(-sum(delta), 0)::int into _v_net
    from public.credit_transactions
    where ref_copy_id = p_copy_id
      and txn_type in ('reserve','consume','refund');
    if _v_net > 0 then
      out_ok := true; out_reason := 'OK_INCLUDED'; out_credits := 0;
      return next; return;
    end if;
  end if;

  _v_needed := _v_total - _v_open;   -- complément éventuel

  if p_establishment_id is not null then
    if not exists (
      select 1 from public.establishment_members
      where establishment_id = p_establishment_id
        and user_id = _v_user_id and is_active = true
    ) then
      out_reason := 'NOT_MEMBER_OF_ESTABLISHMENT'; return next; return;
    end if;
    _v_estab := p_establishment_id;
  else
    select establishment_id into _v_estab
    from public.establishment_members
    where user_id = _v_user_id and is_active = true
    limit 1;
  end if;

  out_credits := _v_total;

  if _v_estab is not null then
    select limit_total, used into _v_quota_limit, _v_quota_used
    from public.teacher_quotas
    where establishment_id = _v_estab and user_id = _v_user_id
    for update;

    if _v_quota_limit is null or _v_quota_limit = 0 then
      out_reason := 'QUOTA_NOT_SET'; return next; return;
    end if;
    out_available := greatest(0, _v_quota_limit - _v_quota_used);
    if _v_quota_used + _v_needed > _v_quota_limit then
      out_reason := 'QUOTA_EXCEEDED'; return next; return;
    end if;

    select coalesce(sum(credits_remaining), 0)::int into _v_available
    from public.credit_lots
    where owner_kind = 'establishment'
      and owner_establishment_id = _v_estab
      and status = 'active' and credits_remaining > 0 and expires_at > now();
    if _v_available < _v_needed then
      out_available := least(out_available, _v_available);
      out_reason := 'NO_CREDITS_IN_POOL'; return next; return;
    end if;

    _v_left := _v_needed;
    for _v_lot in
      select id, credits_remaining from public.credit_lots
      where owner_kind = 'establishment'
        and owner_establishment_id = _v_estab
        and status = 'active' and credits_remaining > 0 and expires_at > now()
      order by expires_at asc
      for update
    loop
      exit when _v_left <= 0;
      _v_take := least(_v_left, _v_lot.credits_remaining);
      update public.credit_lots
        set credits_remaining = credits_remaining - _v_take,
            status = case when credits_remaining - _v_take = 0 then 'exhausted' else status end
        where id = _v_lot.id;
      insert into public.credit_transactions
        (lot_id, user_id, establishment_id, txn_type, delta, reason, ref_copy_id, settled)
      values (_v_lot.id, _v_user_id, _v_estab, 'reserve', -_v_take,
              'copy_reserve_pool', p_copy_id, false);
      _v_first_lot := coalesce(_v_first_lot, _v_lot.id);
      _v_left := _v_left - _v_take;
    end loop;

    update public.teacher_quotas
      set used = used + _v_needed, updated_at = now()
      where establishment_id = _v_estab and user_id = _v_user_id;

    out_ok := true; out_reason := 'OK_POOL'; out_lot_id := _v_first_lot;
    out_remaining_after := greatest(0, _v_quota_limit - _v_quota_used - _v_needed);
    return next; return;
  end if;

  select coalesce(sum(credits_remaining), 0)::int into _v_available
  from public.credit_lots
  where owner_kind = 'user' and owner_user_id = _v_user_id
    and status = 'active' and credits_remaining > 0 and expires_at > now();
  out_available := _v_available;
  if _v_available < _v_needed then
    out_reason := 'NO_CREDITS'; return next; return;
  end if;

  _v_left := _v_needed;
  for _v_lot in
    select id, credits_remaining from public.credit_lots
    where owner_kind = 'user' and owner_user_id = _v_user_id
      and status = 'active' and credits_remaining > 0 and expires_at > now()
    order by expires_at asc
    for update
  loop
    exit when _v_left <= 0;
    _v_take := least(_v_left, _v_lot.credits_remaining);
    update public.credit_lots
      set credits_remaining = credits_remaining - _v_take,
          status = case when credits_remaining - _v_take = 0 then 'exhausted' else status end
      where id = _v_lot.id;
    insert into public.credit_transactions
      (lot_id, user_id, txn_type, delta, reason, ref_copy_id, settled)
    values (_v_lot.id, _v_user_id, 'reserve', -_v_take, 'copy_reserve', p_copy_id, false);
    _v_first_lot := coalesce(_v_first_lot, _v_lot.id);
    _v_left := _v_left - _v_take;
  end loop;

  out_ok := true; out_reason := 'OK_PERSONAL'; out_lot_id := _v_first_lot;
  out_remaining_after := _v_available - _v_needed;
  return next;
end;
$$;


-- Remboursement interne (aucune vérification d'appelant) : utilisé par
-- refund_credits() et par le balayage serveur. Jamais exposé à l'app.
create or replace function public.refund_copy_charge_internal(
  p_copy_id uuid,
  p_reason text default 'api_error'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_total int := 0;
  _v_row record;
begin
  for _v_row in
    select lot_id, user_id, establishment_id, -sum(delta)::int as amount
    from public.credit_transactions
    where ref_copy_id = p_copy_id
      and txn_type in ('reserve','consume')
      and settled = false
    group by lot_id, user_id, establishment_id
    having -sum(delta) > 0
  loop
    update public.credit_lots
      set credits_remaining = credits_remaining + _v_row.amount,
          status = case when status = 'exhausted' then 'active' else status end
      where id = _v_row.lot_id
        and status in ('active','exhausted');

    if _v_row.establishment_id is not null then
      update public.teacher_quotas
        set used = greatest(used - _v_row.amount, 0), updated_at = now()
        where establishment_id = _v_row.establishment_id
          and user_id = _v_row.user_id;
    end if;

    insert into public.credit_transactions
      (lot_id, user_id, establishment_id, txn_type, delta, reason, ref_copy_id, settled)
    values (_v_row.lot_id, _v_row.user_id, _v_row.establishment_id,
            'refund', _v_row.amount, coalesce(p_reason, 'api_error'), p_copy_id, true);

    _v_total := _v_total + _v_row.amount;
  end loop;

  update public.credit_transactions
    set settled = true
    where ref_copy_id = p_copy_id
      and txn_type in ('reserve','consume')
      and settled = false;

  return _v_total;
end;
$$;

-- Remboursement : le prof ne peut se faire rembourser qu'une copie en erreur
-- dont la dernière réservation a plus de 3 minutes (la correction serveur
-- dure ~90 s max). Le serveur (service_role, auth.uid() null) rembourse sans
-- délai.
create or replace function public.refund_credits(
  p_copy_id uuid,
  p_reason text default 'api_error'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_caller uuid := auth.uid();
  _v_owner uuid;
  _v_status text;
  _v_last_reserve timestamptz;
begin
  if _v_caller is not null then
    select e.owner_id, c.status::text into _v_owner, _v_status
    from public.student_copies c
    join public.exams e on e.id = c.exam_id
    where c.id = p_copy_id;
    if _v_owner is null or _v_owner <> _v_caller then return 0; end if;
    if _v_status <> 'error' then return 0; end if;
    select max(created_at) into _v_last_reserve
    from public.credit_transactions
    where ref_copy_id = p_copy_id and txn_type in ('reserve','consume') and settled = false;
    if _v_last_reserve is not null and _v_last_reserve > now() - interval '3 minutes' then
      return 0;
    end if;
  end if;
  return public.refund_copy_charge_internal(p_copy_id, p_reason);
end;
$$;

-- Balayage quotidien (appelé avec l'expiration des lots) :
--   - copie corrigée mais débit resté en suspens → débit définitif
--   - débit en suspens depuis > 30 min sur une copie non corrigée → remboursé
create or replace function public.settle_stale_charges()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_copy record;
  _v_count int := 0;
begin
  for _v_copy in
    select t.ref_copy_id as copy_id, c.status::text as status
    from public.credit_transactions t
    left join public.student_copies c on c.id = t.ref_copy_id
    where t.settled = false
      and t.txn_type in ('reserve','consume')
      and t.ref_copy_id is not null
    group by t.ref_copy_id, c.status
    having max(t.created_at) < now() - interval '30 minutes'
  loop
    if _v_copy.status = 'graded' then
      perform public.finalize_copy_charge(_v_copy.copy_id);
    else
      perform public.refund_copy_charge_internal(_v_copy.copy_id, 'stale_reservation');
    end if;
    _v_count := _v_count + 1;
  end loop;
  return _v_count;
end;
$$;
revoke execute on function public.settle_stale_charges() from public, anon, authenticated;
grant execute on function public.settle_stale_charges() to service_role;

create or replace function public.expire_credits_job()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_count int := 0;
  _v_lot record;
begin
  -- D'abord solder les débits en suspens (rend les crédits avant expiration)
  perform public.settle_stale_charges();

  for _v_lot in
    select * from public.credit_lots
    where status = 'active'
      and expires_at <= now()
      and credits_remaining > 0
    for update
  loop
    insert into public.credit_transactions
      (lot_id, user_id, establishment_id, txn_type, delta, reason, settled)
    values (
      _v_lot.id,
      case when _v_lot.owner_kind = 'user' then _v_lot.owner_user_id end,
      case when _v_lot.owner_kind = 'establishment' then _v_lot.owner_establishment_id end,
      'expire', -_v_lot.credits_remaining, 'cron_expired', true
    );
    update public.credit_lots
      set credits_remaining = 0, status = 'expired'
      where id = _v_lot.id;
    _v_count := _v_count + 1;
  end loop;
  return _v_count;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- A8. Anti force brute sur teacher_join_school (email école + identifiant)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.join_attempts (
  id          bigserial primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  ok          boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists join_attempts_user_idx on public.join_attempts(user_id, created_at desc);
alter table public.join_attempts enable row level security;
drop policy if exists "join_attempts deny" on public.join_attempts;
create policy "join_attempts deny" on public.join_attempts for all using (false);

CREATE OR REPLACE FUNCTION public.teacher_join_school(p_school_email text, p_join_code text)
 RETURNS TABLE(out_ok boolean, out_reason text, out_establishment_id uuid, out_establishment_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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

  -- Audit 15/10/2026 : anti force brute des identifiants (choisis par
  -- l'admin, donc souvent devinables) — 10 échecs max par heure et par compte.
  if (select count(*) from public.join_attempts
       where user_id = _v_user_id and ok = false
         and created_at > now() - interval '1 hour') >= 10 then
    out_ok := false; out_reason := 'TOO_MANY_ATTEMPTS';
    return next; return;
  end if;

  select * into _v_slot
  from public.establishment_teacher_slots
  where school_email = p_school_email and join_code = p_join_code;

  if _v_slot is null then
    insert into public.join_attempts (user_id, ok) values (_v_user_id, false);
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

-- ─────────────────────────────────────────────────────────────────────────────
-- A9. Copies d'élèves : plus de listing public du bucket
-- ─────────────────────────────────────────────────────────────────────────────
-- Les policies « Public read » sur storage.objects permettaient à n'importe
-- qui (clé anon) de LISTER tous les fichiers des buckets copies/subjects,
-- donc de retrouver et télécharger les copies de tous les élèves. Les URL
-- publiques (getPublicUrl) ne passent pas par ces policies et continuent de
-- fonctionner ; chaque prof garde l'accès complet à son propre dossier.
drop policy if exists "Public read copy files" on storage.objects;
drop policy if exists "Public read subject files" on storage.objects;

-- ─────────────────────────────────────────────────────────────────────────────
-- A7. RPC réservées aux comptes connectés (plus d'exécution par anon)
-- ─────────────────────────────────────────────────────────────────────────────
-- Par défaut PostgreSQL accorde EXECUTE à PUBLIC (donc à anon, la clé publique
-- embarquée dans l'APK). On retire ce droit, on le rend aux comptes connectés,
-- puis on retire aux comptes connectés les fonctions purement serveur.
revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;

revoke execute on function public.finalize_copy_charge(uuid) from authenticated;
revoke execute on function public.expire_credits_job() from authenticated;
revoke execute on function public.settle_stale_charges() from authenticated;
revoke execute on function public.refund_copy_charge_internal(uuid, text) from authenticated;
revoke execute on function public.authorize_grading(uuid, boolean) from authenticated;
revoke execute on function public.complete_payment_order(uuid, text, text, jsonb) from authenticated;

-- Aperçu d'une invitation avant connexion (écran d'acceptation)
grant execute on function public.get_invitation_info(text) to anon;

-- Les helpers RLS n'acceptent plus d'interroger un autre utilisateur que soi.
create or replace function public.user_admin_establishments(uid uuid)
returns setof uuid
language sql
stable
security definer
set search_path = public
as $$
  select establishment_id
  from public.establishment_members
  where user_id = uid
    and uid = auth.uid()
    and role = 'admin';
$$;

-- Fonction trigger sans search_path fixe (bonne pratique SECURITY DEFINER)
alter function public.handle_new_establishment() set search_path = public;
