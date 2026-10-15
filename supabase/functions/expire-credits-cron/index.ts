// =============================================================================
// Job d'expiration quotidien des lots de crédits
// =============================================================================
// À planifier via Supabase Scheduled Functions :
//   - Frequence : tous les jours à 00h01 UTC
//   - Cron : "1 0 * * *"
//
// Appelle la RPC SQL `expire_credits_job()` qui :
//   1. Cherche tous les lots actifs avec expires_at <= now() et credits_remaining > 0
//   2. Passe leur status à 'expired', credits_remaining à 0
//   3. Trace dans credit_transactions (txn_type='expire')
//   4. Retourne le nombre de lots expirés
//
// Depuis le 15/10/2026, le même job supprime aussi les comptes dont la
// demande de suppression a plus de 30 jours (cf. _shared/account_purge.ts).
//
// Sécurité : appelée par le Scheduler Supabase avec service_role → bypass RLS.
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';
import { purgeDueAccounts } from '../_shared/account_purge.ts';

// Audit 15/10/2026 — fonction réservée au serveur (Scheduler / admin).
// Sans ce contrôle, n'importe qui disposant de la clé publique de l'app
// pouvait l'appeler. Accepté : clé service_role en Bearer, ou en-tête
// x-cron-secret égal au secret CRON_SECRET (si défini).
function isServerCaller(req: Request): boolean {
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const cronSecret = Deno.env.get('CRON_SECRET') ?? '';
  const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  const cronHeader = req.headers.get('x-cron-secret') ?? '';
  const eq = (a: string, b: string) => {
    if (!a || !b || a.length !== b.length) return false;
    let r = 0;
    for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return r === 0;
  };
  return eq(bearer, serviceKey) || (cronSecret !== '' && eq(cronHeader, cronSecret));
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

Deno.serve(async (req) => {
  const startedAt = new Date().toISOString();
  if (!isServerCaller(req)) {
    return new Response(JSON.stringify({ ok: false, error: 'Forbidden' }), {
      status: 403,
      headers: { 'content-type': 'application/json' },
    });
  }
  try {
    const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data, error } = await client.rpc('expire_credits_job');
    if (error) {
      console.error('[expire-credits-cron] RPC erreur', error);
      return new Response(
        JSON.stringify({ ok: false, error: error.message, startedAt }),
        { status: 500, headers: { 'content-type': 'application/json' } },
      );
    }
    const count = (data as number | null) ?? 0;
    console.log(
      `[expire-credits-cron] ${count} lots expirés (${startedAt})`,
    );

    // Comptes dont la suppression (demandée il y a 30 jours) est échue.
    // Une erreur ici ne fait pas échouer le job d'expiration.
    let accountsDeleted = 0;
    let accountsFailed = 0;
    try {
      const results = await purgeDueAccounts(client);
      accountsDeleted = results.filter((r) => r.ok).length;
      accountsFailed = results.length - accountsDeleted;
      for (const r of results.filter((r) => !r.ok)) {
        console.warn(`[expire-credits-cron] compte ${r.userId} non supprimé : ${r.error}`);
      }
    } catch (e) {
      console.error('[expire-credits-cron] purge comptes échouée', e);
    }
    console.log(
      `[expire-credits-cron] ${accountsDeleted} compte(s) supprimé(s), ${accountsFailed} en échec`,
    );
    return new Response(
      JSON.stringify({
        ok: true,
        expired_count: count,
        accounts_deleted: accountsDeleted,
        accounts_failed: accountsFailed,
        startedAt,
      }),
      { status: 200, headers: { 'content-type': 'application/json' } },
    );
  } catch (e) {
    console.error('[expire-credits-cron] exception', e);
    return new Response(
      JSON.stringify({ ok: false, error: String(e), startedAt }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }
});
