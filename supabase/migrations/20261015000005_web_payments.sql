-- =============================================================================
-- Option B (15/10/2026) : les crédits s'achètent sur la page web
-- correctis.app/credits, plus dans l'app (règle Google Play sur les achats
-- de contenus numériques). Le paiement reste CinetPay ; l'app ne fait plus
-- qu'utiliser les crédits.
--
--   1. get_my_purchase_context : tout ce dont la page a besoin en un appel
--      (type de compte, pays de facturation, écoles administrées).
--   2. create_payment_order : choix explicite de l'école pour un admin de
--      plusieurs écoles (avant : la première trouvée).
--   3. get_my_payment_order : détail d'une commande pour la page de retour.
--
-- Idempotente.
-- =============================================================================


-- 1. Contexte d'achat du compte connecté
create or replace function public.get_my_purchase_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  _v_uid uuid := auth.uid();
  _v_profile record;
  _v_schools jsonb;
begin
  if _v_uid is null then raise exception 'Non authentifié.'; end if;

  select email, display_name, account_type, billing_country
    into _v_profile
  from public.profiles where id = _v_uid;

  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'name', e.name)
                            order by e.name), '[]'::jsonb)
    into _v_schools
  from public.establishments e
  where e.id in (
    select m.establishment_id from public.establishment_members m
     where m.user_id = _v_uid and m.role = 'admin' and m.is_active
  );

  return jsonb_build_object(
    'email', _v_profile.email,
    'display_name', _v_profile.display_name,
    'account_type', _v_profile.account_type,
    'billing_country', _v_profile.billing_country,
    'currency', public.billing_currency_for(_v_profile.billing_country),
    'can_change_country', not exists (
      select 1 from public.payment_orders
       where buyer_user_id = _v_uid and status = 'completed'
    ),
    'admin_schools', _v_schools
  );
end;
$$;
revoke execute on function public.get_my_purchase_context() from public, anon;
grant execute on function public.get_my_purchase_context() to authenticated;


-- 2. Création de commande avec école explicite
drop function if exists public.create_payment_order(text, text);
drop function if exists public.create_payment_order(text, text, uuid);

create function public.create_payment_order(
  p_pack_code text,
  p_target_kind text default 'user',        -- 'user' ou 'establishment'
  p_establishment_id uuid default null       -- école choisie (admin)
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
    select m.establishment_id into _v_target_estab
    from public.establishment_members m
    where m.user_id = _v_user_id and m.role = 'admin' and m.is_active = true
      and (p_establishment_id is null or m.establishment_id = p_establishment_id)
    order by m.joined_at
    limit 1;
    if _v_target_estab is null then
      raise exception 'NOT_SCHOOL_ADMIN'
        using hint = 'Seul un administrateur de l''école peut acheter pour elle.';
    end if;
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
revoke execute on function public.create_payment_order(text, text, uuid) from public, anon;
grant execute on function public.create_payment_order(text, text, uuid) to authenticated;


-- 3. Détail d'une commande de l'acheteur (page de retour après CinetPay)
create or replace function public.get_my_payment_order(p_order_id uuid)
returns table (
  out_status text,
  out_pack_name text,
  out_credits int,
  out_amount bigint,
  out_currency text,
  out_target_kind text,
  out_failure_reason text,
  out_paid_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select o.status, p.name, o.copies_count, o.amount, o.amount_currency,
         o.target_kind, o.failure_reason, o.paid_at
  from public.payment_orders o
  left join public.credit_packs p on p.code = o.pack_code
  where o.id = p_order_id
    and o.buyer_user_id = auth.uid();
$$;
revoke execute on function public.get_my_payment_order(uuid) from public, anon;
grant execute on function public.get_my_payment_order(uuid) to authenticated;
