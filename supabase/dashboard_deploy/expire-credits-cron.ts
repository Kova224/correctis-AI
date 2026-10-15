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

// ── Copie de _shared/account_purge.ts (version tableau de bord, un seul fichier) ──
// =============================================================================
// Suppression définitive des comptes arrivés au bout du délai de 30 jours.
// Utilisé par :
//   - expire-credits-cron (job quotidien, déjà planifié) ;
//   - delete-account (lancement manuel par le support).
//
// Pour chaque compte dû, dans cet ordre (chaque étape peut être rejouée) :
//   1. effacer ses fichiers (copies, sujets, avatar) via l'API Storage ;
//   2. purge_account_data : anonymise les paiements, supprime les examens
//      solo, garde les examens d'école sans photos ;
//   3. supprimer l'utilisateur Auth → profil, adhésions, quotas, crédits
//      personnels partent en cascade.
// Si une étape échoue, le compte reste dans la liste et sera retenté au
// passage suivant.
// =============================================================================

// deno-lint-ignore no-explicit-any
type Client = any;

export type PurgeResult = {
  userId: string;
  ok: boolean;
  filesDeleted?: number;
  data?: unknown;
  error?: string;
};

const STORAGE_BATCH = 100;

export async function purgeAccount(client: Client, userId: string): Promise<PurgeResult> {
  // Sécurité : on revérifie que la suppression est bien demandée et échue.
  const { data: prof, error: profErr } = await client
    .from("profiles")
    .select("id, deletion_scheduled_for")
    .eq("id", userId)
    .maybeSingle();
  if (profErr) return { userId, ok: false, error: profErr.message };
  if (!prof?.deletion_scheduled_for || new Date(prof.deletion_scheduled_for) > new Date()) {
    return { userId, ok: false, error: "NOT_DUE" };
  }

  // 1. Fichiers
  const { data: objects, error: listErr } = await client.rpc("list_user_storage_objects", {
    p_user_id: userId,
  });
  if (listErr) return { userId, ok: false, error: `storage list: ${listErr.message}` };
  const byBucket = new Map<string, string[]>();
  for (const o of (objects ?? []) as { out_bucket: string; out_name: string }[]) {
    if (!o.out_name.startsWith(`${userId}/`)) continue; // ceinture et bretelles
    const list = byBucket.get(o.out_bucket) ?? [];
    list.push(o.out_name);
    byBucket.set(o.out_bucket, list);
  }
  let filesDeleted = 0;
  for (const [bucket, names] of byBucket) {
    for (let i = 0; i < names.length; i += STORAGE_BATCH) {
      const chunk = names.slice(i, i + STORAGE_BATCH);
      const { error } = await client.storage.from(bucket).remove(chunk);
      if (error) return { userId, ok: false, error: `storage remove ${bucket}: ${error.message}` };
      filesDeleted += chunk.length;
    }
  }

  // 2. Données en base
  const { data: purge, error: purgeErr } = await client.rpc("purge_account_data", {
    p_user_id: userId,
  });
  if (purgeErr) return { userId, ok: false, filesDeleted, error: `purge: ${purgeErr.message}` };
  if (!purge?.ok) {
    // Devenu propriétaire / seul admin entre-temps : on ne supprime pas.
    return { userId, ok: false, filesDeleted, data: purge, error: purge?.blocker ?? "BLOCKED" };
  }

  // 3. Compte Auth
  const { error: delErr } = await client.auth.admin.deleteUser(userId);
  if (delErr) return { userId, ok: false, filesDeleted, data: purge, error: `auth: ${delErr.message}` };

  return { userId, ok: true, filesDeleted, data: purge };
}

export async function purgeDueAccounts(client: Client, limit = 50): Promise<PurgeResult[]> {
  const { data, error } = await client.rpc("list_due_account_deletions", { p_limit: limit });
  if (error) throw new Error(`list_due_account_deletions: ${error.message}`);
  const results: PurgeResult[] = [];
  for (const row of (data ?? []) as { out_user_id: string }[]) {
    try {
      results.push(await purgeAccount(client, row.out_user_id));
    } catch (e) {
      results.push({ userId: row.out_user_id, ok: false, error: String(e) });
    }
  }
  return results;
}

// ── Fin de la copie ──


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
