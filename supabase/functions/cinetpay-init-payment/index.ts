// =============================================================================
// CinetPay Aurore (v1) — Initialisation d'un paiement
// =============================================================================
// Reçoit : { order_id: uuid, payment_method: 'OM'|'MTN'|'WAVE'|'MOOV'|'AIRTEL'|'CARD' }
//
// Grille v5 (sept. 2026) : la devise et le pays viennent de la commande
// (payment_orders.amount_currency / country_code), fixés à partir du pays de
// facturation du compte. XOF pour BJ/BF/CI/ML/NE/SN/TG, GNF pour GN.
// Carte bancaire (VISA_<PAYS>, couvre Visa et Mastercard) : refusée tant que
// le secret CINETPAY_CARD_ENABLED ne vaut pas 1. CinetPay doit d'abord activer
// l'option carte sur le compte marchand (sinon « payment method invalide »).
// Retourne : { payment_url, transaction_id, notify_token }
//
// Flow Aurore :
//   1. Auth Supabase (JWT requis).
//   2. Charge l'ordre payment_orders (statut='pending', buyer = user).
//   3. POST /v1/oauth/login avec {api_key, api_password} → Bearer token.
//   4. POST /v1/payment avec Authorization: Bearer <token> et le body Aurore.
//   5. Stocke transaction_id + notify_token + payment_url côté DB.
//   6. Retourne payment_url au mobile.
//
// ⚠️ Proxy VPS : CinetPay exige une whitelist IP fixe qui est incompatible
// avec les IPs dynamiques des Edge Functions Supabase. Toutes les requêtes
// passent donc par un proxy VPS Hetzner (Caddy reverse proxy) dont l'IP est
// whitelistée chez CinetPay. Le secret CINETPAY_PROXY_URL (ex: http://IP_VPS)
// remplace l'URL directe api.cinetpay.net.
//
// Variables d'env Supabase :
//   - CINETPAY_API_KEY        (account_key dans la console)
//   - CINETPAY_SECRET_KEY     (mot de passe API)
//   - CINETPAY_PROXY_URL      (http://IP_VPS — obligatoire pour bypasser la
//                              whitelist IP de CinetPay)
//   - CINETPAY_NOTIFY_URL     (URL publique de cinetpay-webhook Supabase)
//   - CINETPAY_RETURN_URL     (page web après paiement — option B :
//                              https://correctis.app/credits/ ; l'identifiant
//                              de la commande est ajouté en ?order=<id>)
//   - CINETPAY_FAILED_URL     (page web après échec — optionnel, même page
//                              par défaut)
//   - CINETPAY_ENV            ('TEST' Sandbox ou 'PROD')
//   - CINETPAY_COUNTRY        (repli uniquement : le pays vient désormais de
//                              la commande — payment_orders.country_code)
//   - SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto)
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const CINETPAY_API_KEY = Deno.env.get('CINETPAY_API_KEY') ?? '';
const CINETPAY_SECRET_KEY = Deno.env.get('CINETPAY_SECRET_KEY') ?? '';
const CINETPAY_NOTIFY_URL = Deno.env.get('CINETPAY_NOTIFY_URL') ?? '';
const CINETPAY_RETURN_URL = Deno.env.get('CINETPAY_RETURN_URL') ?? '';
const CINETPAY_FAILED_URL = Deno.env.get('CINETPAY_FAILED_URL') ?? CINETPAY_RETURN_URL;
const CINETPAY_ENV = (Deno.env.get('CINETPAY_ENV') ?? 'TEST').toUpperCase();
const CINETPAY_COUNTRY = (Deno.env.get('CINETPAY_COUNTRY') ?? 'GN').toUpperCase();

// URL du proxy VPS avec IP fixe whitelistée chez CinetPay.
// Fallback sur api.cinetpay.net direct si non défini (ne marchera pas en prod
// à cause de la whitelist IP).
const CINETPAY_PROXY_URL_RAW = Deno.env.get('CINETPAY_PROXY_URL') ?? '';
const CINETPAY_BASE_URL =
  CINETPAY_PROXY_URL_RAW || 'https://api.cinetpay.net';
// Audit 15/10/2026 : la clé et le mot de passe API CinetPay transitent par
// ce proxy. En production, un proxy en http:// (en clair) est refusé.
const PROXY_INSECURE = CINETPAY_BASE_URL.startsWith('http://');

// Secret partage avec Caddy — protege le proxy contre les abus.
// Genere par setup-proxy-secret.sh sur le VPS. Doit etre le meme dans
// le Caddyfile ET dans le secret Supabase CINETPAY_PROXY_SECRET.
//
// ⚠️ IMPORTANT : on lit l'env A CHAQUE APPEL (pas au chargement du module),
// car si le secret est ajoute/modifie APRES le premier boot de la fonction,
// une constante top-level resterait vide et le header serait envoye vide.
function proxyHeaders(): Record<string, string> {
  const secret = Deno.env.get('CINETPAY_PROXY_SECRET') ?? '';
  const usesProxy = !CINETPAY_BASE_URL.includes('api.cinetpay.net');
  return usesProxy && secret
    ? { 'X-Correctis-Proxy': secret }
    : {};
}

// Log de démarrage — nous permet de savoir dans les logs Supabase si le
// secret CINETPAY_PROXY_URL est bien pris en compte ou si on tombe sur le
// fallback api.cinetpay.net (auquel cas CinetPay répondra code:2011).
console.log('[cinetpay-init] boot', {
  proxyUrlSet: CINETPAY_PROXY_URL_RAW.length > 0,
  proxyUrlLength: CINETPAY_PROXY_URL_RAW.length,
  proxyUrlPrefix: CINETPAY_PROXY_URL_RAW.slice(0, 8), // ex "http://1" — pas la clé
  baseUrlUsed: CINETPAY_BASE_URL.startsWith('https://api.cinetpay')
    ? 'DIRECT (fallback)'
    : 'PROXY',
});

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// Option B (15/10/2026) : la page web d'achat retrouve la commande au retour
// de CinetPay grâce à ?order=<id>. CinetPay limite ces URL à 120 caractères :
// au-delà, on renvoie l'URL de base (la page relit alors la dernière commande
// gardée dans le navigateur).
function returnUrlFor(base: string, orderId: string): string {
  if (!base) return CINETPAY_NOTIFY_URL.substring(0, 120);
  const withOrder = `${base}${base.includes('?') ? '&' : '?'}order=${orderId}`;
  return withOrder.length <= 120 ? withOrder : base.substring(0, 120);
}

interface InitRequest {
  order_id: string;
  payment_method: string;
  phone_number?: string; // Saisi sur la page web d'achat (numero mobile client)
}

// Numeros Sandbox test par pays/operateur (utilises comme fallback en TEST
// quand aucun numero client n'est fourni). Cf. doc CinetPay :
// GN Orange : 62222xxxx, suffixe 0700 = succes immediat.
const SANDBOX_TEST_PHONES: Record<string, string> = {
  'GN_OM': '+224622220700',
  'GN_MTN': '+224622220700', // pas de MTN natif en GN, fallback OM
  'GN_WAVE': '+224622220700',
  'GN_MOOV': '+224622220700',
  'GN_CARD': '+224622220700',
  'CI_OM': '+2250707070700',
  'CI_MTN': '+2250505050500',
};

// Pays facturés en XOF (CinetPay) — la Guinée est facturée en GNF.
const XOF_COUNTRIES = new Set(['BJ', 'BF', 'CI', 'ML', 'NE', 'SN', 'TG']);

// Opérateurs Mobile Money proposés par pays (codes courts, envoyés à CinetPay
// sous la forme <CODE>_<PAYS>). Vérifiés le 15/10/2026 avec le tableau
// « Méthodes de paiement » de CinetPay (encaissement disponible).
// ⚠️ À garder synchronisé avec infra/web/credits/app.js (COUNTRIES) et
// lib/models/billing.dart (BillingCountry).
const OPERATORS_BY_COUNTRY: Record<string, string[]> = {
  BJ: ['MTN', 'MOOV'],
  BF: ['OM', 'MOOV', 'WAVE'],
  CI: ['OM', 'MTN', 'MOOV', 'WAVE'],
  GN: ['OM', 'MTN'],
  ML: ['OM', 'MOOV'],
  NE: ['AIRTEL', 'MOOV'],
  SN: ['OM', 'WAVE', 'FREE'],
  TG: ['MOOV', 'TMONEY'],
};

function cors(headers: Record<string, string> = {}) {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers':
      'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    ...headers,
  };
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: cors({ 'content-type': 'application/json' }),
  });
}

Deno.serve(async (req) => {
  try {
    return await handleRequest(req);
  } catch (e) {
    // Attrape TOUTE exception non-catchee pour eviter le 502 EDGE_FUNCTION_ERROR
    // et logger le stacktrace precisement.
    console.error('[cinetpay-init] UNCAUGHT', {
      message: (e as any)?.message,
      stack: (e as any)?.stack,
      raw: String(e),
    });
    return jsonError('Erreur serveur interne (voir logs)', 500);
  }
});

async function handleRequest(req: Request): Promise<Response> {
  console.log('[cinetpay-init] req received', {
    method: req.method,
    url: req.url,
  });
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: cors() });
  }
  if (req.method !== 'POST') {
    return jsonError('Method not allowed', 405);
  }

  // ── 0. Validation des secrets ──
  if (!CINETPAY_API_KEY || !CINETPAY_SECRET_KEY || !CINETPAY_NOTIFY_URL) {
    return jsonError(
      'CinetPay non configuré (CINETPAY_API_KEY / CINETPAY_SECRET_KEY / CINETPAY_NOTIFY_URL manquants)',
      500,
    );
  }

  if (CINETPAY_ENV === 'PROD' && PROXY_INSECURE) {
    console.error('[cinetpay-init] CINETPAY_PROXY_URL en http:// refusé en PROD');
    return jsonError(
      'Paiement indisponible : configuration du proxy CinetPay non sécurisée (https requis).',
      503,
    );
  }

  // ── 1. Auth Supabase (JWT du prof) ──
  const authHeader = req.headers.get('Authorization') ?? '';
  const jwt = authHeader.replace(/^Bearer\s+/i, '').trim();
  if (!jwt) return jsonError('Non authentifié', 401);

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: userRes, error: userErr } = await supabase.auth.getUser(jwt);
  if (userErr || !userRes?.user) return jsonError('Session invalide', 401);
  const userId = userRes.user.id;

  // ── 2. Parse body ──
  let body: InitRequest;
  try {
    body = await req.json();
  } catch {
    return jsonError('Body invalide', 400);
  }
  if (!body.order_id || !body.payment_method) {
    return jsonError('Paramètres manquants : order_id, payment_method', 400);
  }

  // ── 3. Charge l'ordre (service_role pour bypasser RLS DENY) ──
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: order, error: orderErr } = await admin
    .from('payment_orders')
    .select(
      'id, buyer_user_id, target_kind, pack_code, copies_count, amount, amount_gnf, amount_fcfa, amount_currency, country_code, status',
    )
    .eq('id', body.order_id)
    .maybeSingle();
  if (orderErr || !order) return jsonError('Ordre introuvable', 404);
  if (order.buyer_user_id !== userId) {
    return jsonError('Cet ordre ne vous appartient pas', 403);
  }
  if (order.status !== 'pending') {
    return jsonError(`Ordre déjà ${order.status}`, 409);
  }

  // ── 3b. Devise / pays / montant de la commande ──
  const orderCurrency = ((order.amount_currency as string) || 'GNF').toUpperCase();
  const orderCountry = ((order.country_code as string) || CINETPAY_COUNTRY).toUpperCase();
  const orderAmount = Number(order.amount ?? order.amount_gnf ?? 0);
  if (!orderAmount || orderAmount <= 0) {
    return jsonError('Montant de la commande invalide', 400);
  }
  const expectedCurrency = orderCountry === 'GN' ? 'GNF' : 'XOF';
  if (!XOF_COUNTRIES.has(orderCountry) && orderCountry !== 'GN') {
    return jsonError(`Pays non couvert par CinetPay : ${orderCountry}`, 400);
  }
  if (orderCurrency !== expectedCurrency) {
    return jsonError(
      `Devise incohérente (${orderCurrency}) pour le pays ${orderCountry}`,
      400,
    );
  }
  const allowedOps = OPERATORS_BY_COUNTRY[orderCountry] ?? [];
  const cardEnabled = Deno.env.get('CINETPAY_CARD_ENABLED') === '1';
  if (body.payment_method === 'CARD' && !cardEnabled) {
    return jsonError(
      'Le paiement par carte n\'est pas encore disponible. Utilisez Mobile Money.',
      400,
    );
  }
  if (body.payment_method !== 'CARD' && !allowedOps.includes(body.payment_method)) {
    return jsonError(
      `Moyen de paiement ${body.payment_method} indisponible pour ce pays.`,
      400,
    );
  }

  // ── 4. Charge le profil pour le client_* ──
  const { data: profile } = await admin
    .from('profiles')
    .select('display_name, email, phone')
    .eq('id', userId)
    .maybeSingle();

  const fullName = (profile?.display_name as string) ||
    (profile?.email as string) ||
    'Utilisateur Correctis';
  const customerEmail = (profile?.email as string) ||
    `${userId}@correctis.local`;
  const [firstName, ...rest] = fullName.split(' ');
  const lastName = rest.join(' ') || 'Correctis';
  const safeFirst = (firstName.length >= 2 ? firstName : firstName + 'r').substring(0, 255);
  const safeLast = (lastName.length >= 2 ? lastName : lastName + 'r').substring(0, 255);

  // ── 5. merchant_transaction_id (≤ 30 chars selon doc Aurore) ──
  const shortId = order.id.replace(/-/g, '').substring(0, 8);
  const shortNow = Date.now().toString(36).toUpperCase();
  const merchantTxnId = `CORR-${shortId}-${shortNow}`.substring(0, 30);

  // ── 6. Login OAuth pour récupérer le Bearer token ──
  let accessToken: string;
  try {
    const headersUsed = {
      'content-type': 'application/json',
      ...proxyHeaders(),
    };
    console.log('[cinetpay-init] login attempt', {
      baseUrl: CINETPAY_BASE_URL,
      hasProxySecret: !!Deno.env.get('CINETPAY_PROXY_SECRET'),
      proxySecretLen: (Deno.env.get('CINETPAY_PROXY_SECRET') ?? '').length,
      sendsProxyHeader: 'X-Correctis-Proxy' in headersUsed,
    });
    const loginResp = await fetch(`${CINETPAY_BASE_URL}/v1/oauth/login`, {
      method: 'POST',
      headers: headersUsed,
      body: JSON.stringify({
        api_key: CINETPAY_API_KEY,
        api_password: CINETPAY_SECRET_KEY,
      }),
    });
    const respText = await loginResp.text();
    console.log('[cinetpay-init] login response', {
      status: loginResp.status,
      contentType: loginResp.headers.get('content-type'),
      bodyLen: respText.length,
      bodyStart: respText.substring(0, 200),
    });
    let loginJson: any = null;
    try {
      loginJson = JSON.parse(respText);
    } catch {
      loginJson = null;
    }
    if (!loginJson) {
      console.error('[cinetpay-init] login non-JSON', {
        status: loginResp.status,
        body: respText.substring(0, 200),
      });
      return jsonError(
        `CinetPay login : réponse non JSON (status ${loginResp.status})`,
        502,
      );
    }
    accessToken = loginJson.access_token ||
      loginJson.token ||
      loginJson?.data?.access_token ||
      loginJson?.data?.token ||
      '';
    if (!accessToken) {
      console.error('[cinetpay-init] login KO', {
        code: loginJson.code,
        message: loginJson.message,
        status: loginJson.status,
      });
      return jsonError(
        loginJson.message ?? 'CinetPay login refusé (vérifie API_KEY/SECRET_KEY)',
        502,
      );
    }
  } catch (e) {
    console.error('[cinetpay-init] login fetch error', String(e));
    return jsonError('CinetPay injoignable (oauth/login)', 502);
  }

  // ── 7. Init paiement /v1/payment ──
  const designation =
    `Pack ${order.pack_code} - ${order.copies_count} credits Correctis`
      .substring(0, 150);

  // Aurore exige <OPERATOR>_<COUNTRY> (ex: OM_GN). L'app envoie le code court
  // (OM, MTN, WAVE, MOOV, CARD), on ajoute le pays ici.
  // Cas spécial : CARD devient VISA_<COUNTRY>.
  const opCode = body.payment_method === 'CARD' ? 'VISA' : body.payment_method;
  const paymentMethodFull = `${opCode}_${orderCountry}`;

  // ── Determine le numero mobile client ──
  // Priorite : body.phone_number > profile.phone.
  // Le numero est OBLIGATOIRE : CinetPay le refuse s'il est absent ou
  // invalide (erreur "client_phone_number is not mobile").
  //
  // La page web d'achat collecte le numero. En Sandbox, si
  // ALLOW_SANDBOX_PHONE_FALLBACK=1 est defini, on autorise un fallback
  // pour tests infra (ne PAS activer en production).
  const rawPhone = (body.phone_number ?? '').trim() ||
    ((profile?.phone as string) ?? '').trim();
  const phoneRegex = /^\+\d{10,15}$/;
  let clientPhone = phoneRegex.test(rawPhone) ? rawPhone : '';

  if (!clientPhone) {
    const allowSandboxFallback =
      Deno.env.get('ALLOW_SANDBOX_PHONE_FALLBACK') === '1';
    if (CINETPAY_ENV === 'TEST' && allowSandboxFallback) {
      clientPhone = SANDBOX_TEST_PHONES[`${orderCountry}_${opCode}`] ??
        SANDBOX_TEST_PHONES['GN_OM'];
      console.warn(
        '[cinetpay-init] no valid phone, using Sandbox test number',
        { used: clientPhone },
      );
    } else {
      console.warn('[cinetpay-init] phone missing or invalid', {
        received: rawPhone.substring(0, 4) + '***',
      });
      return jsonError(
        'Numéro de téléphone invalide. Format attendu : indicatif pays (ex. +225) suivi du numéro mobile.',
        400,
      );
    }
  }

  // Devise = celle du compte de l'acheteur (XOF ou GNF), jamais convertie.
  const paymentPayload = {
    currency: orderCurrency,
    payment_method: paymentMethodFull,
    merchant_transaction_id: merchantTxnId,
    amount: orderAmount,
    lang: 'fr',
    designation,
    client_email: customerEmail,
    client_phone_number: clientPhone,
    client_first_name: safeFirst,
    client_last_name: safeLast,
    success_url: returnUrlFor(CINETPAY_RETURN_URL, order.id),
    failed_url: returnUrlFor(CINETPAY_FAILED_URL, order.id),
    notify_url: CINETPAY_NOTIFY_URL.substring(0, 120),
    direct_pay: false,
  };

  let paymentJson: any;
  let paymentStatus = 0;
  try {
    // Log ce qu'on envoie (utile pour debug format Aurore)
    console.log('[cinetpay-init] payment payload sent', {
      currency: paymentPayload.currency,
      payment_method: paymentPayload.payment_method,
      amount: paymentPayload.amount,
      merchant_transaction_id: paymentPayload.merchant_transaction_id,
      // PII masquées dans les logs (audit 15/10/2026)
      client_phone_number: paymentPayload.client_phone_number.slice(0, 5) + '***',
      client_email: paymentPayload.client_email.replace(/^(.).*(@.*)$/, '$1***$2'),
      notify_url: paymentPayload.notify_url,
      success_url: paymentPayload.success_url,
    });

    const paymentResp = await fetch(`${CINETPAY_BASE_URL}/v1/payment`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'authorization': `Bearer ${accessToken}`,
        ...proxyHeaders(),
      },
      body: JSON.stringify(paymentPayload),
    });
    paymentStatus = paymentResp.status;
    paymentJson = await paymentResp.json().catch(() => null);
    if (!paymentJson) return jsonError('CinetPay : réponse non JSON', 502);
  } catch (e) {
    console.error('[cinetpay-init] payment fetch error', String(e));
    return jsonError('CinetPay injoignable (/v1/payment)', 502);
  }

  const isOk = paymentJson.code === 200 || paymentJson.code === '200';
  const paymentUrl = paymentJson.payment_url || paymentJson?.data?.payment_url || '';
  const notifyToken = paymentJson.notify_token || paymentJson?.data?.notify_token || '';
  const cinetpayTxnId = paymentJson.transaction_id || paymentJson?.data?.transaction_id || '';
  const paymentToken = paymentJson.payment_token || paymentJson?.data?.payment_token || '';

  if (!isOk || !paymentUrl) {
    // Log la reponse COMPLETE pour voir tous les champs du details
    console.error('[cinetpay-init] init KO — full response', {
      http_status: paymentStatus,
      full_response: JSON.stringify(paymentJson),
    });
    console.error('[cinetpay-init] init KO', {
      code: paymentJson.code,
      status: paymentJson.status,
      message: paymentJson.message,
      details_status: paymentJson?.details?.status,
      details_message: paymentJson?.details?.message,
      details: JSON.stringify(paymentJson?.details),
      errors: JSON.stringify(paymentJson?.errors),
    });
    await admin
      .from('payment_orders')
      .update({
        status: 'failed',
        failed_at: new Date().toISOString(),
        failure_reason:
          paymentJson.message ?? paymentJson?.details?.message ?? 'Init refusé',
        cinetpay_payload: paymentJson,
      })
      .eq('id', order.id);
    return jsonError(
      paymentJson.message ?? 'CinetPay a refusé la transaction',
      502,
    );
  }

  // ── 8. Persiste les références CinetPay côté DB ──
  await admin
    .from('payment_orders')
    .update({
      cinetpay_transaction_id: merchantTxnId, // = merchant_transaction_id (notre ref)
      cinetpay_cinetpay_txn_id: cinetpayTxnId, // = transaction_id côté CinetPay
      cinetpay_notify_token: notifyToken,
      cinetpay_payment_url: paymentUrl,
      cinetpay_payment_method: body.payment_method,
      cinetpay_payment_token: paymentToken,
    })
    .eq('id', order.id);

  return new Response(
    JSON.stringify({
      payment_url: paymentUrl,
      transaction_id: cinetpayTxnId,
      merchant_transaction_id: merchantTxnId,
      notify_token: notifyToken,
      env: CINETPAY_ENV,
      provider: 'cinetpay',
    }),
    {
      status: 200,
      headers: cors({ 'content-type': 'application/json' }),
    },
  );
}
