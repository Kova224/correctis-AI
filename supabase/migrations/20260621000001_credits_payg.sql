-- =============================================================================
-- Sprint 4 — EduCorrect Pay-as-you-go (système de crédits)
-- Réf : "Concept et fonctionnement complet du système Pay-as-you-go" (juin 2026)
-- =============================================================================
-- Principes appliqués :
--   1. Deux soldes JAMAIS confondus : crédits applicatifs (cette DB) vs solde
--      réel des APIs (Anthropic + Google Cloud, hors DB).
--   2. 1 crédit = 1 copie corrigée par l'IA (OCR + Claude réussis).
--   3. FIFO par date d'expiration — le lot qui expire le plus tôt est consommé
--      en premier.
--   4. 30 jours de validité après confirmation du paiement.
--   5. Le pack Découverte (1-3 copies gratuit) est UNIQUE à vie par compte,
--      tracé via profiles.discovery_used.
--   6. Établissement : pool mutualisé + quotas individuels par prof
--      (un quota atteint bloque la correction sans toucher au pool global).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Flag discovery_used sur les profils (3 copies gratuites à vie)
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.profiles
  add column if not exists discovery_used boolean not null default false;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Catalogue des packs (informatif — la grille reste codée côté Flutter
--    pour permettre des évolutions sans migration, mais on la duplique ici
--    pour traçabilité des achats).
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.credit_packs (
  code             text primary key,           -- 'discovery', 'micro', 'solo_s', ...
  scope            text not null check (scope in ('solo', 'establishment')),
  name             text not null,
  copies_min       int  not null,
  copies_max       int  not null,
  price_fcfa       int  not null,              -- prix en F CFA (entier)
  price_gnf        bigint not null,            -- prix en GNF
  price_usd_cents  int  not null,              -- prix en cents USD pour Stripe éventuel
  is_active        boolean not null default true,
  display_order    int not null default 0,
  marketing_label  text                        -- 'Populaire', 'Pack actuel', etc.
);

insert into public.credit_packs
  (code, scope, name, copies_min, copies_max, price_fcfa, price_gnf, price_usd_cents, display_order, marketing_label)
values
  ('discovery',  'solo', 'Découverte', 1,    3,     0,      0,         0,    0,  null),
  ('micro',      'solo', 'Micro',      4,    15,    1200,   18640,     200,  1,  null),
  ('solo_s',     'solo', 'Solo S',     16,   30,    2200,   34175,     360,  2,  null),
  ('solo_m',     'solo', 'Solo M',     31,   80,    5200,   80785,     860,  3,  'Populaire'),
  ('solo_l',     'solo', 'Solo L',     81,   150,   9900,   153800,    1630, 4,  null),
  ('solo_xl',    'solo', 'Solo XL',    151,  300,   17500,  271845,    2890, 5,  null),
  ('solo_max',   'solo', 'Solo MAX',   301,  500,   26900,  417990,    4440, 6,  null),
  ('estab_small','establishment', 'Petit',       1,    200,   17900,  278150,    2950,  10, null),
  ('estab_mid',  'establishment', 'Moyen',       201,  500,   35900,  557785,    5920,  11, null),
  ('estab_large','establishment', 'Grand lycée', 501,  1000,  62900,  977455,    10380, 12, null),
  ('estab_uni',  'establishment', 'Université',  1001, 2500,  115900, 1801030,   19120, 13, null),
  ('estab_group','establishment', 'Groupe',      2501, 5000,  195900, 3044475,   32310, 14, null)
on conflict (code) do update set
  name = excluded.name,
  copies_min = excluded.copies_min,
  copies_max = excluded.copies_max,
  price_fcfa = excluded.price_fcfa,
  price_gnf = excluded.price_gnf,
  price_usd_cents = excluded.price_usd_cents,
  display_order = excluded.display_order,
  marketing_label = excluded.marketing_label;

-- Permet le SELECT public en lecture seule (catalogue affiché dans l'app).
alter table public.credit_packs enable row level security;
drop policy if exists "credit_packs select all" on public.credit_packs;
create policy "credit_packs select all"
  on public.credit_packs for select using (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Ordres de paiement (CinetPay)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.payment_orders (
  id                     uuid primary key default gen_random_uuid(),
  -- Qui paie
  buyer_user_id          uuid not null references auth.users(id) on delete cascade,
  -- Destination des crédits (établissement si admin, sinon = buyer)
  target_kind            text not null check (target_kind in ('user','establishment')),
  target_user_id         uuid references auth.users(id),
  target_establishment_id uuid references public.establishments(id) on delete cascade,
  -- Pack acheté
  pack_code              text not null references public.credit_packs(code),
  copies_count           int not null,                 -- copies allouées (= max du pack)
  -- Montants — la Guinée utilise GNF comme devise de compte CinetPay,
  -- on stocke donc le GNF en montant principal. Le FCFA reste informatif
  -- pour le reporting (la grille tarifaire d'origine est en FCFA).
  amount_gnf             bigint not null,
  amount_fcfa            int    not null,
  amount_currency        text   not null default 'GNF',
  -- État
  status                 text not null default 'pending'
                          check (status in ('pending','completed','failed','refunded')),
  -- CinetPay Aurore (v1) — Sandbox & prod
  -- merchant_transaction_id : généré côté nous (ex: CORR-xxx), envoyé à CinetPay,
  --                            renvoyé dans le webhook → permet de retrouver l'ordre.
  -- transaction_id (côté CinetPay) : retourné par /v1/payment à l'init.
  -- notify_token : retourné par /v1/payment, à comparer avec celui du webhook
  --                pour valider l'authenticité (anti-spoof).
  cinetpay_transaction_id      text unique,            -- = notre merchant_transaction_id
  cinetpay_cinetpay_txn_id     text,                    -- = transaction_id côté CinetPay
  cinetpay_notify_token        text,                    -- = jeton anti-spoof du webhook
  cinetpay_payment_method      text,                    -- 'OM','MTN','WAVE','MOOV','CARD'
  cinetpay_payment_url         text,                    -- URL hosted page
  cinetpay_payment_token       text,                    -- payment_token (info)
  cinetpay_payload             jsonb,                   -- raw webhook payload
  -- Timestamps
  created_at             timestamptz not null default now(),
  paid_at                timestamptz,
  failed_at              timestamptz,
  failure_reason         text,
  -- Contraintes : si target_kind='user' alors target_user_id requis, etc.
  constraint payment_target_consistent check (
    (target_kind = 'user' and target_user_id is not null and target_establishment_id is null)
    or
    (target_kind = 'establishment' and target_establishment_id is not null)
  )
);
create index if not exists payment_orders_buyer_idx on public.payment_orders(buyer_user_id, created_at desc);
create index if not exists payment_orders_estab_idx on public.payment_orders(target_establishment_id) where target_establishment_id is not null;
create index if not exists payment_orders_status_idx on public.payment_orders(status);

alter table public.payment_orders enable row level security;
drop policy if exists "payment_orders deny" on public.payment_orders;
create policy "payment_orders deny"
  on public.payment_orders for all using (false);
-- → Lecture/écriture uniquement via RPCs SECURITY DEFINER (jamais directement).

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Lots de crédits (un lot = un achat ou un don Découverte)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.credit_lots (
  id                       uuid primary key default gen_random_uuid(),
  -- Propriétaire du lot
  owner_kind               text not null check (owner_kind in ('user','establishment')),
  owner_user_id            uuid references auth.users(id) on delete cascade,
  owner_establishment_id   uuid references public.establishments(id) on delete cascade,
  -- Source
  source                   text not null check (source in ('purchase','discovery','admin_grant')),
  pack_code                text references public.credit_packs(code),
  payment_order_id         uuid references public.payment_orders(id) on delete set null,
  -- Comptabilité crédits
  credits_total            int not null check (credits_total > 0),
  credits_remaining        int not null check (credits_remaining >= 0),
  -- Validité 30 jours
  purchased_at             timestamptz not null default now(),
  expires_at               timestamptz not null,
  -- Statut
  status                   text not null default 'active'
                            check (status in ('active','exhausted','expired','revoked')),
  notes                    text,
  constraint lot_owner_consistent check (
    (owner_kind = 'user' and owner_user_id is not null and owner_establishment_id is null)
    or
    (owner_kind = 'establishment' and owner_establishment_id is not null)
  ),
  constraint lot_credits_le_total check (credits_remaining <= credits_total)
);
-- Index FIFO : on retire les crédits du lot dont expires_at est le plus proche.
create index if not exists credit_lots_user_fifo_idx
  on public.credit_lots(owner_user_id, expires_at)
  where owner_kind = 'user' and status = 'active';
create index if not exists credit_lots_estab_fifo_idx
  on public.credit_lots(owner_establishment_id, expires_at)
  where owner_kind = 'establishment' and status = 'active';

alter table public.credit_lots enable row level security;
drop policy if exists "credit_lots deny" on public.credit_lots;
create policy "credit_lots deny"
  on public.credit_lots for all using (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Journal des transactions de crédits (audit non modifiable)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.credit_transactions (
  id                   uuid primary key default gen_random_uuid(),
  lot_id               uuid references public.credit_lots(id) on delete cascade,
  user_id              uuid references auth.users(id) on delete cascade,
  establishment_id     uuid references public.establishments(id) on delete cascade,
  txn_type             text not null check (txn_type in
                          ('grant','reserve','consume','refund','expire','revoke')),
  delta                int not null,                       -- positif = ajout, négatif = retrait
  reason               text,                                -- 'discovery'|'purchase'|'copy_graded'|'api_error'|'cron_expired'|...
  ref_copy_id          uuid references public.student_copies(id) on delete set null,
  ref_payment_order_id uuid references public.payment_orders(id) on delete set null,
  created_at           timestamptz not null default now()
);
create index if not exists credit_txn_user_idx on public.credit_transactions(user_id, created_at desc);
create index if not exists credit_txn_estab_idx on public.credit_transactions(establishment_id, created_at desc) where establishment_id is not null;

alter table public.credit_transactions enable row level security;
drop policy if exists "credit_txn deny" on public.credit_transactions;
create policy "credit_txn deny"
  on public.credit_transactions for all using (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Quotas individuels par prof dans une école
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.teacher_quotas (
  id                uuid primary key default gen_random_uuid(),
  establishment_id  uuid not null references public.establishments(id) on delete cascade,
  user_id           uuid not null references auth.users(id) on delete cascade,
  limit_total       int not null default 0,                -- 0 = pas de quota, illimité dans la limite du pool
  used              int not null default 0,
  updated_at        timestamptz not null default now(),
  unique (establishment_id, user_id)
);
alter table public.teacher_quotas enable row level security;
drop policy if exists "teacher_quotas deny" on public.teacher_quotas;
create policy "teacher_quotas deny"
  on public.teacher_quotas for all using (false);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. RPC : Grant Discovery (3 crédits gratuits à vie par compte)
-- ─────────────────────────────────────────────────────────────────────────────
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
  _v_used    boolean;
  _v_lot_id  uuid;
  _v_exp     timestamptz;
begin
  if _v_user_id is null then
    raise exception 'Non authentifié.';
  end if;

  -- Vérifie le flag discovery_used
  select coalesce(discovery_used, false) into _v_used
  from public.profiles
  where id = _v_user_id;

  if _v_used is true then
    out_lot_id := null;
    out_credits := 0;
    out_expires_at := null;
    out_already_used := true;
    return next;
    return;
  end if;

  _v_exp := now() + interval '30 days';

  insert into public.credit_lots (
    owner_kind, owner_user_id, source, pack_code,
    credits_total, credits_remaining, purchased_at, expires_at, status
  ) values (
    'user', _v_user_id, 'discovery', 'discovery',
    3, 3, now(), _v_exp, 'active'
  )
  returning id into _v_lot_id;

  update public.profiles set discovery_used = true where id = _v_user_id;

  insert into public.credit_transactions
    (lot_id, user_id, txn_type, delta, reason)
  values
    (_v_lot_id, _v_user_id, 'grant', 3, 'discovery');

  out_lot_id := _v_lot_id;
  out_credits := 3;
  out_expires_at := _v_exp;
  out_already_used := false;
  return next;
end;
$$;
grant execute on function public.grant_discovery_credits() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Trigger : à la création d'un profil, accorder automatiquement Découverte
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.auto_grant_discovery_on_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_exp timestamptz := now() + interval '30 days';
  _v_lot_id uuid;
begin
  if coalesce(new.discovery_used, false) then
    return new;
  end if;
  insert into public.credit_lots (
    owner_kind, owner_user_id, source, pack_code,
    credits_total, credits_remaining, purchased_at, expires_at, status
  ) values (
    'user', new.id, 'discovery', 'discovery',
    3, 3, now(), _v_exp, 'active'
  )
  returning id into _v_lot_id;
  new.discovery_used := true;
  insert into public.credit_transactions
    (lot_id, user_id, txn_type, delta, reason)
  values
    (_v_lot_id, new.id, 'grant', 3, 'discovery');
  return new;
end;
$$;

drop trigger if exists profiles_auto_discovery on public.profiles;
create trigger profiles_auto_discovery
  before insert on public.profiles
  for each row execute function public.auto_grant_discovery_on_signup();

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. RPC : Get my credit wallet (solde global + prochaine expiration)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_credit_wallet()
returns table (
  out_total_credits int,
  out_active_lots_count int,
  out_next_expiration timestamptz,
  out_next_expiration_credits int,
  out_discovery_used boolean
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then return; end if;

  return query
  select
    coalesce(sum(credits_remaining), 0)::int,
    count(*)::int,
    min(expires_at) filter (where credits_remaining > 0),
    (select credits_remaining from public.credit_lots l2
       where l2.owner_kind = 'user' and l2.owner_user_id = _v_user_id
         and l2.status = 'active' and l2.credits_remaining > 0
       order by expires_at asc limit 1),
    (select coalesce(discovery_used, false) from public.profiles where id = _v_user_id)
  from public.credit_lots
  where owner_kind = 'user'
    and owner_user_id = _v_user_id
    and status = 'active'
    and credits_remaining > 0;
end;
$$;
grant execute on function public.get_my_credit_wallet() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. RPC : Get my credit lots (détail FIFO)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_credit_lots()
returns table (
  out_id uuid,
  out_pack_code text,
  out_pack_name text,
  out_source text,
  out_credits_total int,
  out_credits_remaining int,
  out_purchased_at timestamptz,
  out_expires_at timestamptz,
  out_status text
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then return; end if;

  return query
  select
    l.id,
    l.pack_code,
    coalesce(p.name, l.pack_code),
    l.source,
    l.credits_total,
    l.credits_remaining,
    l.purchased_at,
    l.expires_at,
    l.status
  from public.credit_lots l
  left join public.credit_packs p on p.code = l.pack_code
  where l.owner_kind = 'user'
    and l.owner_user_id = _v_user_id
    and l.status in ('active','exhausted')
  order by l.expires_at asc;
end;
$$;
grant execute on function public.get_my_credit_lots() to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RPC : Get my credit history (activité récente)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_my_credit_history(p_limit int default 30)
returns table (
  out_id uuid,
  out_txn_type text,
  out_delta int,
  out_reason text,
  out_pack_name text,
  out_payment_amount_gnf bigint,
  out_payment_amount_fcfa int,
  out_payment_currency text,
  out_payment_method text,
  out_payment_status text,
  out_created_at timestamptz
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then return; end if;
  return query
  select
    t.id,
    t.txn_type,
    t.delta,
    t.reason,
    coalesce(p.name, ''),
    o.amount_gnf,
    o.amount_fcfa,
    o.amount_currency,
    o.cinetpay_payment_method,
    o.status,
    t.created_at
  from public.credit_transactions t
  left join public.payment_orders o on o.id = t.ref_payment_order_id
  left join public.credit_packs p on p.code = coalesce(o.pack_code,
       (select pack_code from public.credit_lots l where l.id = t.lot_id))
  where t.user_id = _v_user_id
  order by t.created_at desc
  limit p_limit;
end;
$$;
grant execute on function public.get_my_credit_history(int) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. RPC : Réserver 1 crédit (avant correction) — FIFO + SELECT FOR UPDATE
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.reserve_credit(p_copy_id uuid)
returns table (
  out_ok boolean,
  out_lot_id uuid,
  out_remaining_after int,
  out_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_lot_id  uuid;
  _v_rem     int;
  _v_owner_estab uuid;
  _v_pool_lot uuid;
  _v_quota_limit int;
  _v_quota_used int;
begin
  if _v_user_id is null then
    out_ok := false; out_reason := 'NOT_AUTHENTICATED';
    return next; return;
  end if;

  -- 1. Tente d'abord le wallet personnel (FIFO)
  select id, credits_remaining
    into _v_lot_id, _v_rem
  from public.credit_lots
  where owner_kind = 'user'
    and owner_user_id = _v_user_id
    and status = 'active'
    and credits_remaining > 0
    and expires_at > now()
  order by expires_at asc
  limit 1
  for update;

  if _v_lot_id is not null then
    update public.credit_lots
      set credits_remaining = credits_remaining - 1,
          status = case when credits_remaining - 1 = 0 then 'exhausted' else status end
      where id = _v_lot_id;
    insert into public.credit_transactions
      (lot_id, user_id, txn_type, delta, reason, ref_copy_id)
    values (_v_lot_id, _v_user_id, 'reserve', -1, 'copy_reserve', p_copy_id);
    out_ok := true; out_lot_id := _v_lot_id; out_remaining_after := _v_rem - 1;
    out_reason := 'OK_PERSONAL';
    return next; return;
  end if;

  -- 2. Sinon : pool établissement (si l'user est prof actif)
  select establishment_id into _v_owner_estab
  from public.establishment_members
  where user_id = _v_user_id and is_active = true
  limit 1;

  if _v_owner_estab is not null then
    -- Vérifie quota individuel
    select limit_total, used into _v_quota_limit, _v_quota_used
    from public.teacher_quotas
    where establishment_id = _v_owner_estab and user_id = _v_user_id;

    if _v_quota_limit is not null and _v_quota_limit > 0
       and _v_quota_used >= _v_quota_limit then
      out_ok := false; out_reason := 'QUOTA_EXCEEDED';
      return next; return;
    end if;

    -- Prélève sur le pool établissement (FIFO)
    select id, credits_remaining
      into _v_pool_lot, _v_rem
    from public.credit_lots
    where owner_kind = 'establishment'
      and owner_establishment_id = _v_owner_estab
      and status = 'active'
      and credits_remaining > 0
      and expires_at > now()
    order by expires_at asc
    limit 1
    for update;

    if _v_pool_lot is not null then
      update public.credit_lots
        set credits_remaining = credits_remaining - 1,
            status = case when credits_remaining - 1 = 0 then 'exhausted' else status end
        where id = _v_pool_lot;
      update public.teacher_quotas
        set used = used + 1, updated_at = now()
        where establishment_id = _v_owner_estab and user_id = _v_user_id;
      insert into public.credit_transactions
        (lot_id, user_id, establishment_id, txn_type, delta, reason, ref_copy_id)
      values (_v_pool_lot, _v_user_id, _v_owner_estab, 'reserve', -1, 'copy_reserve_pool', p_copy_id);
      out_ok := true; out_lot_id := _v_pool_lot; out_remaining_after := _v_rem - 1;
      out_reason := 'OK_POOL';
      return next; return;
    end if;
  end if;

  out_ok := false; out_reason := 'NO_CREDITS';
  return next;
end;
$$;
grant execute on function public.reserve_credit(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. RPC : Confirmer la consommation d'1 crédit (après correction OK)
--    En pratique reserve_credit() suffit (il a déjà décrémenté). Cette RPC
--    est là pour marquer le txn comme 'consume' (audit propre).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.consume_credit(p_copy_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
begin
  if _v_user_id is null then return; end if;
  update public.credit_transactions
    set txn_type = 'consume', reason = 'copy_graded'
    where user_id = _v_user_id
      and ref_copy_id = p_copy_id
      and txn_type = 'reserve';
end;
$$;
grant execute on function public.consume_credit(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. RPC : Rembourser 1 crédit (en cas d'échec IA après 3 retries)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.refund_credit(p_copy_id uuid, p_reason text default 'api_error')
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_lot_id  uuid;
  _v_estab_id uuid;
begin
  if _v_user_id is null then return false; end if;

  select lot_id, establishment_id into _v_lot_id, _v_estab_id
  from public.credit_transactions
  where user_id = _v_user_id
    and ref_copy_id = p_copy_id
    and txn_type = 'reserve'
  limit 1;

  if _v_lot_id is null then return false; end if;

  update public.credit_lots
    set credits_remaining = credits_remaining + 1,
        status = case when status = 'exhausted' then 'active' else status end
    where id = _v_lot_id;

  if _v_estab_id is not null then
    update public.teacher_quotas
      set used = greatest(used - 1, 0), updated_at = now()
      where establishment_id = _v_estab_id and user_id = _v_user_id;
  end if;

  insert into public.credit_transactions
    (lot_id, user_id, establishment_id, txn_type, delta, reason, ref_copy_id)
  values (_v_lot_id, _v_user_id, _v_estab_id, 'refund', 1, p_reason, p_copy_id);
  return true;
end;
$$;
grant execute on function public.refund_credit(uuid, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. RPC : Job d'expiration quotidien (à appeler depuis CRON 00:01 UTC)
-- ─────────────────────────────────────────────────────────────────────────────
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
  for _v_lot in
    select * from public.credit_lots
    where status = 'active'
      and expires_at <= now()
      and credits_remaining > 0
    for update
  loop
    insert into public.credit_transactions
      (lot_id, user_id, establishment_id, txn_type, delta, reason)
    values (
      _v_lot.id,
      case when _v_lot.owner_kind = 'user' then _v_lot.owner_user_id end,
      case when _v_lot.owner_kind = 'establishment' then _v_lot.owner_establishment_id end,
      'expire', -_v_lot.credits_remaining, 'cron_expired'
    );
    update public.credit_lots
      set credits_remaining = 0, status = 'expired'
      where id = _v_lot.id;
    _v_count := _v_count + 1;
  end loop;
  return _v_count;
end;
$$;
-- expire_credits_job : appelée uniquement par pg_cron (rôle postgres) ou
-- par l'Edge Function expire-credits-cron (service_role). Aucun user normal
-- n'a besoin d'invalider les crédits — c'est une opération système.
revoke execute on function public.expire_credits_job()
  from public, anon, authenticated;
grant execute on function public.expire_credits_job()
  to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. RPC ADMIN : pool établissement + quotas profs
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_org_credit_wallet()
returns table (
  out_total_credits int,
  out_active_lots_count int,
  out_next_expiration timestamptz,
  out_active_pack_name text,
  out_active_pack_total int
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  return query
  with active_lots as (
    select l.id, l.credits_remaining, l.credits_total, l.expires_at, l.pack_code
    from public.credit_lots l
    where l.owner_kind = 'establishment'
      and l.owner_establishment_id = _v_estab_id
      and l.status = 'active'
      and l.credits_remaining > 0
  )
  select
    coalesce(sum(credits_remaining), 0)::int,
    count(*)::int,
    min(expires_at),
    (select coalesce(p.name, al.pack_code)
       from active_lots al
       left join public.credit_packs p on p.code = al.pack_code
       order by al.expires_at asc
       limit 1),
    (select credits_total from active_lots
       order by expires_at asc limit 1)
  from active_lots;
end;
$$;
grant execute on function public.get_org_credit_wallet() to authenticated;

create or replace function public.get_org_teacher_quotas()
returns table (
  out_user_id uuid,
  out_display_name text,
  out_matiere text,
  out_limit_total int,
  out_used int,
  out_blocked boolean
)
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then return; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then return; end if;

  return query
  select
    m.user_id,
    coalesce(p.display_name, p.email, 'Enseignant'),
    m.matiere,
    coalesce(q.limit_total, 0),
    coalesce(q.used, 0),
    (coalesce(q.limit_total,0) > 0 and coalesce(q.used,0) >= coalesce(q.limit_total,0))
  from public.establishment_members m
  left join public.profiles p on p.id = m.user_id
  left join public.teacher_quotas q
       on q.establishment_id = _v_estab_id and q.user_id = m.user_id
  where m.establishment_id = _v_estab_id
    and m.role = 'teacher'
    and m.is_active = true
  order by coalesce(p.display_name, p.email);
end;
$$;
grant execute on function public.get_org_teacher_quotas() to authenticated;

create or replace function public.update_teacher_quota(p_user_id uuid, p_limit int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_user_id uuid := auth.uid();
  _v_estab_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if p_limit < 0 then raise exception 'Quota négatif interdit.'; end if;
  select establishment_id into _v_estab_id
  from public.establishment_members
  where user_id = _v_user_id and role = 'admin' and is_active = true
  limit 1;
  if _v_estab_id is null then raise exception 'Réservé à l''administrateur.'; end if;

  insert into public.teacher_quotas (establishment_id, user_id, limit_total, used)
  values (_v_estab_id, p_user_id, p_limit, 0)
  on conflict (establishment_id, user_id)
  do update set limit_total = excluded.limit_total, updated_at = now();
end;
$$;
grant execute on function public.update_teacher_quota(uuid, int) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. RPC : créer un ordre de paiement (appelée avant redirection CinetPay)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.create_payment_order(
  p_pack_code text,
  p_target_kind text default 'user'   -- 'user' ou 'establishment'
)
returns table (
  out_order_id uuid,
  out_amount_gnf bigint,
  out_amount_fcfa int,
  out_currency text,
  out_copies_count int,
  out_pack_name text
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
  _v_id uuid;
begin
  if _v_user_id is null then raise exception 'Non authentifié.'; end if;
  if p_target_kind not in ('user','establishment') then
    raise exception 'target_kind invalide';
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

  insert into public.payment_orders (
    buyer_user_id, target_kind, target_user_id, target_establishment_id,
    pack_code, copies_count, amount_gnf, amount_fcfa, amount_currency, status
  ) values (
    _v_user_id, p_target_kind, _v_target_user, _v_target_estab,
    _v_pack.code, _v_pack.copies_max,
    _v_pack.price_gnf, _v_pack.price_fcfa, 'GNF', 'pending'
  )
  returning id into _v_id;

  out_order_id := _v_id;
  out_amount_gnf := _v_pack.price_gnf;
  out_amount_fcfa := _v_pack.price_fcfa;
  out_currency := 'GNF';
  out_copies_count := _v_pack.copies_max;
  out_pack_name := _v_pack.name;
  return next;
end;
$$;
grant execute on function public.create_payment_order(text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 17. RPC : marquer un ordre comme payé (appelée par l'Edge Function webhook
--     CinetPay, JAMAIS directement par le client mobile).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.complete_payment_order(
  p_order_id uuid,
  p_cinetpay_transaction_id text,
  p_payment_method text,
  p_payload jsonb default null
)
returns table (
  out_lot_id uuid,
  out_credits int,
  out_expires_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  _v_order record;
  _v_lot_id uuid;
  _v_exp timestamptz;
begin
  select * into _v_order from public.payment_orders
  where id = p_order_id for update;
  if not found then raise exception 'Ordre inconnu.'; end if;
  if _v_order.status = 'completed' then
    -- Idempotent : déjà traité (webhook renvoyé)
    select id, expires_at into _v_lot_id, _v_exp
    from public.credit_lots where payment_order_id = p_order_id limit 1;
    out_lot_id := _v_lot_id;
    out_credits := _v_order.copies_count;
    out_expires_at := _v_exp;
    return next; return;
  end if;

  update public.payment_orders
    set status = 'completed',
        paid_at = now(),
        cinetpay_transaction_id = p_cinetpay_transaction_id,
        cinetpay_payment_method = p_payment_method,
        cinetpay_payload = coalesce(p_payload, cinetpay_payload)
    where id = p_order_id;

  _v_exp := now() + interval '30 days';

  insert into public.credit_lots (
    owner_kind, owner_user_id, owner_establishment_id,
    source, pack_code, payment_order_id,
    credits_total, credits_remaining, purchased_at, expires_at, status
  ) values (
    _v_order.target_kind, _v_order.target_user_id, _v_order.target_establishment_id,
    'purchase', _v_order.pack_code, p_order_id,
    _v_order.copies_count, _v_order.copies_count, now(), _v_exp, 'active'
  )
  returning id into _v_lot_id;

  insert into public.credit_transactions
    (lot_id, user_id, establishment_id, txn_type, delta, reason, ref_payment_order_id)
  values (
    _v_lot_id,
    case when _v_order.target_kind = 'user' then _v_order.target_user_id end,
    case when _v_order.target_kind = 'establishment' then _v_order.target_establishment_id end,
    'grant', _v_order.copies_count, 'purchase', p_order_id
  );

  out_lot_id := _v_lot_id;
  out_credits := _v_order.copies_count;
  out_expires_at := _v_exp;
  return next;
end;
$$;
-- ⚠️ SÉCURITÉ CRITIQUE : cette RPC SECURITY DEFINER crée un credit_lot
-- (= crédite le wallet de l'utilisateur). Elle ne doit JAMAIS être appelable
-- par un utilisateur authentifié ni par anon — sinon un attaquant pourrait
-- créditer son propre wallet sans payer.
--
-- Elle est appelée UNIQUEMENT par l'Edge Function `cinetpay-webhook` qui :
--   1. Vérifie le notify_token contre celui stocké en DB (anti-spoof)
--   2. Re-vérifie le statut via GET /v1/payment/{merchant_transaction_id}
--      auprès de l'API CinetPay (source de vérité)
--   3. Appelle cette RPC avec ses droits service_role
--
-- Par défaut PostgreSQL grant EXECUTE à PUBLIC, qu'on révoque explicitement.
revoke execute on function public.complete_payment_order(uuid, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_payment_order(uuid, text, text, jsonb)
  to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 18. Backfill : accorder Découverte rétroactivement aux profils existants
-- ─────────────────────────────────────────────────────────────────────────────
do $$
declare
  _r record;
  _v_lot_id uuid;
begin
  for _r in select id from public.profiles where coalesce(discovery_used, false) = false loop
    insert into public.credit_lots (
      owner_kind, owner_user_id, source, pack_code,
      credits_total, credits_remaining, purchased_at, expires_at, status
    ) values (
      'user', _r.id, 'discovery', 'discovery',
      3, 3, now(), now() + interval '30 days', 'active'
    )
    returning id into _v_lot_id;
    update public.profiles set discovery_used = true where id = _r.id;
    insert into public.credit_transactions
      (lot_id, user_id, txn_type, delta, reason)
    values (_v_lot_id, _r.id, 'grant', 3, 'discovery_backfill');
  end loop;
end$$;
