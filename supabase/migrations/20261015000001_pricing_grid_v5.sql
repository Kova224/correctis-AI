-- =============================================================================
-- Grille tarifaire EduCorrect v5 (Michel — Révision Septembre 2026)
-- Remplace la grille « v4 » et toute tarification antérieure
-- (dont 20260903000009_new_pricing_grid.sql).
--
-- Ce que cette migration applique (cf. PDF « EduCorrect_Grille_Tarifaire_v5 ») :
--   1. Deux grilles AUTONOMES : XOF (Bénin, Burkina Faso, Côte d'Ivoire, Mali,
--      Niger, Sénégal, Togo) et GNF (Guinée). Aucune conversion affichée.
--   2. Un compte est rattaché à UN pays de facturation → UNE devise.
--      Les crédits ne sont ni convertibles ni transférables entre devises.
--   3. Barème pages → crédits : 1 crédit = jusqu'à 8 pages.
--        1–8 → 1 · 9–17 → 2 · 18–25 → 3 · 26–34 → 4 · puis +1 / ≈ 8-9 pages
--      Formule exacte : crédits = ceil(2 × pages / 17)
--   4. Seul « Lancer la correction » débite (le scan/upload ne coûte rien).
--      Le débit couvre plusieurs lots si besoin (FIFO par expiration).
--   5. Échec technique → crédits réservés remis en solde immédiatement
--      (y compris quand l'échec arrive côté serveur, en mode async).
--   6. Relance Human-in-the-Loop (zones illisibles) : incluse, 0 crédit.
--   7. Quota prof (établissement) compté en crédits réellement débités.
--   8. Carte bancaire : uniquement en XOF (pas encore disponible en GNF).
--
-- Idempotente : peut être relancée sans casser l'existant.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Pays couverts par CinetPay + devise associée
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.billing_currency_for(p_country text)
returns text
language sql
immutable
as $$
  select case
    when p_country = 'GN' then 'GNF'
    when p_country in ('BJ','BF','CI','ML','NE','SN','TG') then 'XOF'
    else null
  end;
$$;
grant execute on function public.billing_currency_for(text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Pays de facturation du compte (= devise du compte)
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists billing_country text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'profiles_billing_country_chk'
  ) then
    alter table public.profiles
      add constraint profiles_billing_country_chk
      check (billing_country is null
             or billing_country in ('BJ','BF','CI','GN','ML','NE','SN','TG'));
  end if;
end$$;

-- Garde-fou : le pays (donc la devise) ne peut plus changer dès qu'un
-- paiement a été confirmé sur ce compte. Avant le premier paiement, le prof
-- peut encore corriger une erreur de sélection.
create or replace function public.guard_billing_country_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.billing_country is not null
     and new.billing_country is distinct from old.billing_country
     and auth.uid() is not null   -- les opérations système/support passent
     and exists (
       select 1 from public.payment_orders
        where buyer_user_id = old.id and status = 'completed'
     )
  then
    raise exception 'BILLING_COUNTRY_LOCKED'
      using hint = 'La devise du compte est verrouillée après le premier paiement.';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_guard_billing_country on public.profiles;
create trigger profiles_guard_billing_country
  before update of billing_country on public.profiles
  for each row execute function public.guard_billing_country_change();

-- Lecture du pays / devise du compte courant
create or replace function public.get_my_billing()
returns table (
  out_country text,
  out_currency text,
  out_can_change boolean
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_country text;
begin
  if _v_user_id is null then return; end if;
  select billing_country into _v_country from public.profiles where id = _v_user_id;
  out_country := _v_country;
  out_currency := public.billing_currency_for(_v_country);
  out_can_change := not exists (
    select 1 from public.payment_orders
     where buyer_user_id = _v_user_id and status = 'completed'
  );
  return next;
end;
$$;
grant execute on function public.get_my_billing() to authenticated;

-- Choix du pays de facturation
create or replace function public.set_my_billing_country(p_country text)
returns table (
  out_country text,
  out_currency text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if public.billing_currency_for(p_country) is null then
    raise exception 'COUNTRY_NOT_SUPPORTED'
      using hint = 'Pays non couvert par CinetPay.';
  end if;
  update public.profiles set billing_country = p_country where id = _v_user_id;
  out_country := p_country;
  out_currency := public.billing_currency_for(p_country);
  return next;
end;
$$;
grant execute on function public.set_my_billing_country(text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Catalogue v5 — prix XOF et GNF arrondis indépendamment
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.credit_packs
  add column if not exists price_xof bigint;

-- price_fcfa est conservé (lecture par les anciennes versions de l'app) et
-- aligné sur price_xof. price_usd_cents n'est plus utilisé (0).
update public.credit_packs set price_xof = 0,      price_fcfa = 0,      price_gnf = 0,       price_usd_cents = 0 where code = 'discovery';
-- Professeur Solo
update public.credit_packs set price_xof = 450,    price_fcfa = 450,    price_gnf = 7000,    price_usd_cents = 0 where code = 'micro';
update public.credit_packs set price_xof = 875,    price_fcfa = 875,    price_gnf = 13500,   price_usd_cents = 0 where code = 'solo_s';
update public.credit_packs set price_xof = 2300,   price_fcfa = 2300,   price_gnf = 35500,   price_usd_cents = 0 where code = 'solo_m';
update public.credit_packs set price_xof = 4250,   price_fcfa = 4250,   price_gnf = 65500,   price_usd_cents = 0 where code = 'solo_l';
update public.credit_packs set price_xof = 8400,   price_fcfa = 8400,   price_gnf = 130000,  price_usd_cents = 0 where code = 'solo_xl';
update public.credit_packs set price_xof = 14000,  price_fcfa = 14000,  price_gnf = 216500,  price_usd_cents = 0 where code = 'solo_max';
-- Établissement
update public.credit_packs set price_xof = 6000,   price_fcfa = 6000,   price_gnf = 93000,   price_usd_cents = 0 where code = 'estab_small';
update public.credit_packs set price_xof = 14500,  price_fcfa = 14500,  price_gnf = 227000,  price_usd_cents = 0 where code = 'estab_mid';
update public.credit_packs set price_xof = 28500,  price_fcfa = 28500,  price_gnf = 445000,  price_usd_cents = 0 where code = 'estab_large';
update public.credit_packs set price_xof = 70500,  price_fcfa = 70500,  price_gnf = 1095000, price_usd_cents = 0 where code = 'estab_uni';
update public.credit_packs set price_xof = 140000, price_fcfa = 140000, price_gnf = 2165000, price_usd_cents = 0 where code = 'estab_group';

update public.credit_packs set price_xof = price_fcfa where price_xof is null;
alter table public.credit_packs alter column price_xof set not null;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Ordres de paiement : montant + devise + pays de la commande
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.payment_orders
  add column if not exists amount       bigint,
  add column if not exists country_code text;

-- Historique : toutes les commandes passées étaient en GNF (compte Guinée)
update public.payment_orders
   set amount = amount_gnf,
       country_code = coalesce(country_code, 'GN')
 where amount is null;

drop function if exists public.create_payment_order(text, text);

create function public.create_payment_order(
  p_pack_code text,
  p_target_kind text default 'user'   -- 'user' ou 'establishment'
)
returns table (
  out_order_id uuid,
  out_amount bigint,
  out_currency text,
  out_country text,
  out_copies_count int,
  out_pack_name text,
  -- Compatibilité anciennes versions de l'app (ne pas utiliser)
  out_amount_gnf bigint,
  out_amount_fcfa int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_pack record;
  _v_estab_id uuid;
  _v_target_user uuid;
  _v_target_estab uuid;
  _v_country text;
  _v_currency text;
  _v_amount bigint;
  _v_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if p_target_kind not in ('user','establishment') then
    raise exception 'target_kind invalide';
  end if;

  select billing_country into _v_country from public.profiles where id = _v_user_id;
  _v_currency := public.billing_currency_for(_v_country);
  if _v_currency is null then
    raise exception 'BILLING_COUNTRY_REQUIRED'
      using hint = 'Choisissez votre pays de facturation avant d''acheter un pack.';
  end if;

  select * into _v_pack
  from public.credit_packs
  where code = p_pack_code and is_active = true;
  if not found then raise exception 'Pack inconnu : %', p_pack_code; end if;
  if _v_pack.code = 'discovery' then
    raise exception 'Le pack Découverte n''est pas achetable.';
  end if;

  if p_target_kind = 'establishment' then
    if _v_pack.scope <> 'establishment' then
      raise exception 'Ce pack n''est pas destiné aux établissements.';
    end if;
    select establishment_id into _v_estab_id
    from public.establishment_members
    where user_id = _v_user_id and role = 'admin' and is_active = true
    limit 1;
    if _v_estab_id is null then
      raise exception 'Seul un administrateur peut acheter pour l''établissement.';
    end if;
    _v_target_estab := _v_estab_id;
  else
    if _v_pack.scope <> 'solo' then
      raise exception 'Ce pack est destiné aux établissements, pas aux profs solo.';
    end if;
    _v_target_user := _v_user_id;
  end if;

  _v_amount := case when _v_currency = 'GNF' then _v_pack.price_gnf else _v_pack.price_xof end;
  if _v_amount is null or _v_amount <= 0 then
    raise exception 'Prix indisponible pour ce pack.';
  end if;

  insert into public.payment_orders (
    buyer_user_id, target_kind, target_user_id, target_establishment_id,
    pack_code, copies_count,
    amount, amount_currency, country_code,
    amount_gnf, amount_fcfa,
    status
  ) values (
    _v_user_id, p_target_kind, _v_target_user, _v_target_estab,
    _v_pack.code, _v_pack.copies_max,
    _v_amount, _v_currency, _v_country,
    -- colonnes historiques : seule la devise réelle est renseignée
    case when _v_currency = 'GNF' then _v_amount else 0 end,
    case when _v_currency = 'XOF' then _v_amount::int else 0 end,
    'pending'
  )
  returning id into _v_id;

  out_order_id := _v_id;
  out_amount := _v_amount;
  out_currency := _v_currency;
  out_country := _v_country;
  out_copies_count := _v_pack.copies_max;
  out_pack_name := _v_pack.name;
  out_amount_gnf := case when _v_currency = 'GNF' then _v_amount else 0 end;
  out_amount_fcfa := case when _v_currency = 'XOF' then _v_amount::int else 0 end;
  return next;
end;
$$;
grant execute on function public.create_payment_order(text, text) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Barème pages → crédits
-- ─────────────────────────────────────────────────────────────────────────────
-- ceil(2p/17) reproduit exactement le barème du PDF :
--   8→1, 9→2, 17→2, 18→3, 25→3, 26→4, 34→4, 35→5 …
create or replace function public.credits_for_pages(p_pages int)
returns int
language sql
immutable
as $$
  select case
    when coalesce(p_pages, 0) <= 0 then 0
    else (2 * p_pages + 16) / 17
  end;
$$;
grant execute on function public.credits_for_pages(int) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Suivi des débits par copie (« settled »)
-- ─────────────────────────────────────────────────────────────────────────────
-- settled = false : débit en cours (correction lancée, pas encore terminée)
-- settled = true  : débit définitif (correction réussie) ou déjà remboursé
alter table public.credit_transactions
  add column if not exists settled boolean not null default false;

-- Tout l'historique est considéré comme soldé, sauf les réservations très
-- récentes (corrections potentiellement encore en cours au déploiement).
update public.credit_transactions
   set settled = true
 where settled = false
   and not (txn_type in ('reserve','consume') and created_at > now() - interval '1 hour');

create index if not exists credit_txn_copy_open_idx
  on public.credit_transactions(ref_copy_id)
  where ref_copy_id is not null and settled = false;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Réservation multi-crédits (FIFO, multi-lots)
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
  out_credits int,       -- crédits débités par cet appel (ou déjà débités)
  out_pages int,
  out_available int      -- solde utilisable au moment de la vérification
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_owner uuid;
  _v_pages int;
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

  -- 6a. La copie appartient bien au prof (propriétaire de l'examen)
  select e.owner_id, coalesce(array_length(c.page_images, 1), 0)
    into _v_owner, _v_pages
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

  _v_needed := public.credits_for_pages(_v_pages);

  -- 6b. Débit déjà en cours pour cette copie (relance auto, double tap…)
  --     → on ne débite pas une deuxième fois.
  select coalesce(-sum(delta), 0)::int into _v_open
  from public.credit_transactions
  where ref_copy_id = p_copy_id
    and txn_type in ('reserve','consume')
    and settled = false;
  if _v_open > 0 then
    out_ok := true; out_reason := 'OK_ALREADY_RESERVED'; out_credits := _v_open;
    return next; return;
  end if;

  -- 6c. Relance Human-in-the-Loop : incluse dans les crédits déjà débités.
  if p_hitl then
    select coalesce(-sum(delta), 0)::int into _v_net
    from public.credit_transactions
    where ref_copy_id = p_copy_id
      and txn_type in ('reserve','consume','refund');
    if _v_net > 0 then
      out_ok := true; out_reason := 'OK_INCLUDED'; out_credits := 0;
      return next; return;
    end if;
  end if;

  -- 6d. École active (isolation stricte multi-école, cf. 20260901000001)
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

  out_credits := _v_needed;

  -- ═══════ BRANCHE ÉCOLE : pool + quota individuel en crédits ═══════
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

  -- ═══════ BRANCHE SOLO : wallet personnel ═══════
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
revoke execute on function public.reserve_credits(uuid, uuid, boolean) from public, anon;
grant execute on function public.reserve_credits(uuid, uuid, boolean) to authenticated;

-- Ancienne RPC (versions de l'app déjà installées) : même barème par pages.
drop function if exists public.reserve_credit(uuid);
create or replace function public.reserve_credit(
  p_copy_id uuid,
  p_establishment_id uuid default null
)
returns table (
  out_ok boolean,
  out_lot_id uuid,
  out_remaining_after int,
  out_reason text
)
language sql
security definer
set search_path = public
as $$
  select r.out_ok, r.out_lot_id, r.out_remaining_after, r.out_reason
  from public.reserve_credits(p_copy_id, p_establishment_id, false) r;
$$;
revoke execute on function public.reserve_credit(uuid, uuid) from public, anon;
grant execute on function public.reserve_credit(uuid, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Remboursement idempotent (échec technique)
-- ─────────────────────────────────────────────────────────────────────────────
-- Rembourse uniquement le débit EN COURS de la copie (lignes settled=false),
-- lot par lot, et restaure le quota prof. Appeler 2 fois ne rembourse
-- qu'une fois.
--   - service_role (Edge Function grade-copy) : toujours autorisé
--   - prof propriétaire : seulement si la copie est en erreur (évite de se
--     faire rembourser une correction en train d'aboutir)
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
  _v_total int := 0;
  _v_row record;
begin
  if _v_caller is not null then
    select e.owner_id, c.status::text into _v_owner, _v_status
    from public.student_copies c
    join public.exams e on e.id = c.exam_id
    where c.id = p_copy_id;
    if _v_owner is null or _v_owner <> _v_caller then return 0; end if;
    if _v_status <> 'error' then return 0; end if;
  end if;

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
revoke execute on function public.refund_credits(uuid, text) from public, anon;
grant execute on function public.refund_credits(uuid, text) to authenticated, service_role;

-- Ancienne RPC → délègue (corrige au passage le remboursement côté serveur,
-- qui échouait car auth.uid() est null avec la clé service_role).
create or replace function public.refund_credit(p_copy_id uuid, p_reason text default 'api_error')
returns boolean
language sql
security definer
set search_path = public
as $$
  select public.refund_credits(p_copy_id, p_reason) > 0;
$$;
revoke execute on function public.refund_credit(uuid, text) from public, anon;
grant execute on function public.refund_credit(uuid, text) to authenticated, service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Débit définitif (correction réussie) — appelé par grade-copy
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.finalize_copy_charge(p_copy_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_count int;
begin
  update public.credit_transactions
    set txn_type = 'consume', reason = 'copy_graded', settled = true
    where ref_copy_id = p_copy_id
      and txn_type in ('reserve','consume')
      and settled = false;
  get diagnostics _v_count = row_count;
  return _v_count;
end;
$$;
revoke execute on function public.finalize_copy_charge(uuid) from public, anon, authenticated;
grant execute on function public.finalize_copy_charge(uuid) to service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 9. Vérification rapide (affichée dans le SQL Editor)
-- ─────────────────────────────────────────────────────────────────────────────
select code, name, copies_max, price_xof, price_gnf,
       round(price_xof::numeric / nullif(copies_max, 0)) as xof_par_copie,
       round(price_gnf::numeric / nullif(copies_max, 0)) as gnf_par_copie
from public.credit_packs
order by display_order;
