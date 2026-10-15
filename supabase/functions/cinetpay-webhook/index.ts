// =============================================================================
// CinetPay Aurore (v1) — Webhook de notification
// =============================================================================
// CinetPay envoie un POST JSON minimaliste :
//   {
//     "notify_token": "...",
//     "merchant_transaction_id": "CORR-...",
//     "transaction_id": "...",
//     "user": { "name", "email", "phone_number" }
//   }
//
// ⚠️ Règle d'or Aurore (extraite de la doc CinetPay) :
//   "Ne faites JAMAIS confiance au statut transmis dans le webhook. Le
//    payload reçu peut être forgé. La seule source de vérité est la réponse
//    de l'API CinetPay. À chaque réception, appelez GET /v1/payment/
//    {merchant_transaction_id} pour récupérer le statut canonique signé."
//
// Notre implémentation :
//   1. Accepte GET (sondes de santé) → répond 200.
//   2. Sur POST : lit le payload JSON, vérifie que notify_token correspond
//      à celui stocké en DB lors de l'initialisation (anti-spoof).
//   3. Appelle POST /v1/oauth/login pour récupérer un Bearer token.
//   4. Appelle GET /v1/payment/{merchant_transaction_id} pour le statut réel.
//   5. Si status='SUCCESS' → RPC complete_payment_order (idempotente).
//   6. Si status='FAILED' → marque l'ordre failed côté DB.
//   7. Répond TOUJOURS HTTP 200 dans les 10 s (sinon CinetPay réessaie).
//
// Toutes les requêtes vers CinetPay passent par CINETPAY_PROXY_URL (VPS avec
// IP fixe whitelistée). Idem que cinetpay-init-payment.
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

const CINETPAY_API_KEY = Deno.env.get('CINETPAY_API_KEY') ?? '';
const CINETPAY_SECRET_KEY = Deno.env.get('CINETPAY_SECRET_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

// URL du proxy VPS (mêmes explications que dans cinetpay-init-payment).
const CINETPAY_BASE_URL =
  Deno.env.get('CINETPAY_PROXY_URL') ?? 'https://api.cinetpay.net';

// Audit 15/10/2026 : la clé et le mot de passe API CinetPay transitent par
// ce proxy. En production, un proxy en http:// (en clair) est refusé.
const CINETPAY_ENV = (Deno.env.get('CINETPAY_ENV') ?? 'TEST').toUpperCase();
const PROXY_INSECURE = CINETPAY_BASE_URL.startsWith('http://');

// Secret partage avec Caddy (X-Correctis-Proxy).
// Lu a chaque appel pour supporter les changements de secret sans redeploy.
function proxyHeaders(): Record<string, string> {
  const secret = Deno.env.get('CINETPAY_PROXY_SECRET') ?? '';
  const usesProxy = !CINETPAY_BASE_URL.includes('api.cinetpay.net');
  return usesProxy && secret
    ? { 'X-Correctis-Proxy': secret }
    : {};
}

Deno.serve(async (req) => {
  // GET : sondes de santé CinetPay → 200 vide
  if (req.method === 'GET') {
    return new Response('ok', { status: 200 });
  }
  if (req.method !== 'POST') {
    return new Response('ok', { status: 200 });
  }

  // On lance le traitement en arrière-plan et on répond 200 immédiatement.
  // CinetPay attend < 10 s, et on veut éviter les retries.
  const startedAt = Date.now();
  let payload: any = null;
  try {
    payload = await req.json();
  } catch {
    return new Response('ok', { status: 200 });
  }

  const job = processNotification(payload, startedAt).catch((e) => {
    console.error('[cinetpay-webhook] processNotification exception', String(e));
  });
  // @ts-ignore — EdgeRuntime existe sur Supabase Edge Runtime
  if (typeof EdgeRuntime !== 'undefined' && (EdgeRuntime as any).waitUntil) {
    // @ts-ignore
    (EdgeRuntime as any).waitUntil(job);
    return new Response('ok', { status: 200 });
  }
  await job;
  return new Response('ok', { status: 200 });
});

async function processNotification(
  payload: any,
  startedAt: number,
): Promise<void> {
  const notifyToken: string = payload?.notify_token ?? '';
  const merchantTxnId: string = payload?.merchant_transaction_id ?? '';

  if (!merchantTxnId) {
    console.warn('[cinetpay-webhook] merchant_transaction_id manquant');
    return;
  }
  if (CINETPAY_ENV === 'PROD' && PROXY_INSECURE) {
    console.error(
      '[cinetpay-webhook] CINETPAY_PROXY_URL est en http:// en PROD : ' +
        'vérification refusée (identifiants CinetPay en clair). Passez le proxy en https://.',
    );
    return;
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // ── 1. Retrouve l'ordre par merchant_transaction_id ──
  const { data: order, error: orderErr } = await admin
    .from('payment_orders')
    .select('id, status, cinetpay_notify_token, cinetpay_payment_method')
    .eq('cinetpay_transaction_id', merchantTxnId)
    .maybeSingle();
  if (orderErr || !order) {
    console.warn('[cinetpay-webhook] ordre introuvable pour', merchantTxnId);
    return;
  }
  if (order.status === 'completed') {
    console.log('[cinetpay-webhook] ordre déjà completed (idempotence)', order.id);
    return;
  }

  // ── 2. Anti-spoof : compare le notify_token ──
  if (
    order.cinetpay_notify_token &&
    notifyToken &&
    !timingSafeEqual(order.cinetpay_notify_token, notifyToken)
  ) {
    console.error('[cinetpay-webhook] notify_token mismatch — possible spoof', {
      merchantTxnId,
    });
    return;
  }

  // ── 3. Appelle CinetPay pour le statut canonique ──
  let accessToken = '';
  try {
    const loginResp = await fetch(`${CINETPAY_BASE_URL}/v1/oauth/login`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...proxyHeaders(),
      },
      body: JSON.stringify({
        api_key: CINETPAY_API_KEY,
        api_password: CINETPAY_SECRET_KEY,
      }),
    });
    const loginJson: any = await loginResp.json().catch(() => null);
    accessToken = loginJson?.access_token ||
      loginJson?.token ||
      loginJson?.data?.access_token ||
      loginJson?.data?.token ||
      '';
    if (!accessToken) {
      console.error('[cinetpay-webhook] login KO', {
        code: loginJson?.code,
        message: loginJson?.message,
      });
      return;
    }
  } catch (e) {
    console.error('[cinetpay-webhook] login exception', String(e));
    return;
  }

  let canonical: any;
  try {
    const checkResp = await fetch(
      `${CINETPAY_BASE_URL}/v1/payment/${encodeURIComponent(merchantTxnId)}`,
      {
        method: 'GET',
        headers: {
          'content-type': 'application/json',
          'authorization': `Bearer ${accessToken}`,
          ...proxyHeaders(),
        },
      },
    );
    canonical = await checkResp.json().catch(() => null);
    if (!canonical) {
      console.error('[cinetpay-webhook] check : réponse non JSON');
      return;
    }
  } catch (e) {
    console.error('[cinetpay-webhook] check exception', String(e));
    return;
  }

  // Doc Aurore : code 200 + status 'OK' = paiement validé (nouveau format)
  // On tolère aussi code 100 / status 'SUCCESS' (ancien v2, au cas où).
  const status = (canonical.status ?? canonical?.data?.status ?? '').toString();
  const code = canonical.code ?? canonical?.data?.code;

  const isSuccess =
    status === 'SUCCESS' || status === 'OK' ||
    code === 100 || code === '100' ||
    code === 200 || code === '200';
  const isFailed =
    status === 'FAILED' || status === 'ERROR' ||
    code === 600 || code === '600' ||
    code === 422 || code === '422';

  if (isSuccess) {
    const { error: rpcErr } = await admin.rpc('complete_payment_order', {
      p_order_id: order.id,
      p_cinetpay_transaction_id: merchantTxnId,
      p_payment_method: order.cinetpay_payment_method ?? 'UNKNOWN',
      p_payload: { provider: 'cinetpay', canonical },
    });
    if (rpcErr) {
      console.error('[cinetpay-webhook] complete_payment_order erreur', rpcErr);
      return;
    }
    console.log(
      `[cinetpay-webhook] paiement confirmé en ${Date.now() - startedAt}ms`,
      { merchantTxnId, orderId: order.id },
    );
    return;
  }

  if (isFailed) {
    await admin
      .from('payment_orders')
      .update({
        status: 'failed',
        failed_at: new Date().toISOString(),
        failure_reason:
          canonical?.message ?? canonical?.details?.message ?? 'FAILED',
        cinetpay_payload: canonical,
      })
      .eq('id', order.id);
    console.log('[cinetpay-webhook] paiement échoué', { merchantTxnId });
    return;
  }

  console.log('[cinetpay-webhook] statut intermédiaire, attente', { status, code });
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}
