-- =============================================================================
-- Nouvelle grille tarifaire (Michel — sept 2026).
-- Basée sur : coût réel Haiku 4.5 avec prompt caching (~130 GNF/copie) +
-- marge nette ~40% après commission CinetPay (4%).
--
-- Ratio FCFA/GNF utilisé : 15.54 (aligné avec les prix existants)
-- =============================================================================

-- SOLO — ~260-280 FCFA / copie (pas d'économie d'échelle)
update public.credit_packs set
  price_fcfa = 4000,   price_gnf = 62160
  where code = 'micro';        -- 15 copies → 267 F/copie

update public.credit_packs set
  price_fcfa = 8000,   price_gnf = 124320
  where code = 'solo_s';       -- 30 copies → 267 F/copie

update public.credit_packs set
  price_fcfa = 20000,  price_gnf = 310800
  where code = 'solo_m';       -- 80 copies → 250 F/copie (Populaire)

update public.credit_packs set
  price_fcfa = 37000,  price_gnf = 574980
  where code = 'solo_l';       -- 150 copies → 247 F/copie

update public.credit_packs set
  price_fcfa = 70000,  price_gnf = 1087800
  where code = 'solo_xl';      -- 300 copies → 233 F/copie

update public.credit_packs set
  price_fcfa = 115000, price_gnf = 1787100
  where code = 'solo_max';     -- 500 copies → 230 F/copie

-- ÉTABLISSEMENT — ~200-240 FCFA / copie (économies d'échelle)
update public.credit_packs set
  price_fcfa = 48000,  price_gnf = 745920
  where code = 'estab_small';  -- 200 copies → 240 F/copie

update public.credit_packs set
  price_fcfa = 115000, price_gnf = 1787100
  where code = 'estab_mid';    -- 500 copies → 230 F/copie

update public.credit_packs set
  price_fcfa = 220000, price_gnf = 3418800
  where code = 'estab_large';  -- 1000 copies → 220 F/copie

update public.credit_packs set
  price_fcfa = 525000, price_gnf = 8158500
  where code = 'estab_uni';    -- 2500 copies → 210 F/copie

update public.credit_packs set
  price_fcfa = 1000000, price_gnf = 15540000
  where code = 'estab_group';  -- 5000 copies → 200 F/copie
