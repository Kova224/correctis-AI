-- =============================================================================
-- Fix incrémental pour la migration credits_payg
-- À exécuter dans Supabase Studio → SQL Editor → coller tout → Run
-- =============================================================================
-- Pourquoi : la première version de la migration a déjà créé les fonctions
-- get_my_credit_history et create_payment_order avec une certaine signature.
-- Les nouvelles versions changent le type de retour (ajout out_amount_gnf,
-- out_payment_currency, etc.) → PostgreSQL refuse CREATE OR REPLACE.
-- Solution : DROP avant de re-créer + ajouter les colonnes manquantes à
-- payment_orders si elles n'existent pas déjà.
-- =============================================================================

-- ── 1. Ajouter les colonnes GNF + nouvelles colonnes CinetPay Aurore ─────────
alter table public.payment_orders
  add column if not exists amount_gnf  bigint,
  add column if not exists cinetpay_cinetpay_txn_id text,
  add column if not exists cinetpay_notify_token    text,
  add column if not exists cinetpay_payment_token   text;

-- Backfill amount_gnf depuis le pack pour les ordres déjà existants en pending
update public.payment_orders po
   set amount_gnf = p.price_gnf
  from public.credit_packs p
 where po.amount_gnf is null
   and po.pack_code = p.code;

-- Une fois rempli, on rend la colonne NOT NULL (les futurs INSERT en auront besoin)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='payment_orders'
      and column_name='amount_gnf' and is_nullable='YES'
  ) then
    alter table public.payment_orders alter column amount_gnf set not null;
  end if;
end$$;

-- Devise par défaut GNF (compte CinetPay Guinée)
alter table public.payment_orders
  alter column amount_currency set default 'GNF';

-- ── 2. DROP des fonctions à signature changée ────────────────────────────────
drop function if exists public.get_my_credit_history(integer);
drop function if exists public.create_payment_order(text, text);

-- ── 3. Re-création get_my_credit_history avec amount_gnf + currency ─────────
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

-- ── 4. Re-création create_payment_order avec amount_gnf + currency ──────────
create or replace function public.create_payment_order(
  p_pack_code text,
  p_target_kind text default 'user'
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

-- ── 5. Vérification : retourne quelques infos pour confirmer ────────────────
select
  'payment_orders.amount_gnf existe :' as check_name,
  (exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='payment_orders'
      and column_name='amount_gnf'
  ))::text as ok;
