-- =============================================================================
-- 20261015000006 — Un compte admin ne peut pas acheter de pack solo
-- =============================================================================
-- La page d'achat ne propose déjà que les packs école à un compte « admin ».
-- Le serveur l'impose maintenant aussi : un appel direct à l'API qui
-- demanderait un pack solo pour un compte admin est refusé (ADMIN_NO_SOLO_PACK).
-- Même signature que la version du fichier 000005 : les droits sont conservés.
-- =============================================================================

create or replace function public.create_payment_order(
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
    -- Un compte admin corrige avec les crédits de l'école : des crédits
    -- personnels lui seraient inutilisables.
    if exists (select 1 from public.profiles
               where id = _v_user_id and account_type = 'admin') then
      raise exception 'ADMIN_NO_SOLO_PACK'
        using hint = 'Un compte administrateur achète des packs pour son école.';
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
