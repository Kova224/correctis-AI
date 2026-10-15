// =============================================================================
// Edge Function : delete-account  (réservée au serveur / support)
// =============================================================================
// Supprime définitivement les comptes dont le délai de 30 jours est écoulé.
// Le job quotidien expire-credits-cron fait déjà ce travail chaque nuit ;
// cette fonction sert au support pour traiter une demande tout de suite :
//
//   1. SQL Editor : select * from admin_request_account_deletion('email@x', 0);
//   2. Appeler cette fonction avec la clé service_role :
//        POST /functions/v1/delete-account   body : {}  (ou { "userId": "..." })
//
// Côté app, la demande et l'annulation passent par les RPC
// request_account_deletion / cancel_account_deletion (pas par ici).
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { purgeAccount, purgeDueAccounts } from "../_shared/account_purge.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function isServerCaller(req: Request): boolean {
  const serviceKey = SUPABASE_SERVICE_ROLE_KEY;
  const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
  const bearer = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  const cronHeader = req.headers.get("x-cron-secret") ?? "";
  const eq = (a: string, b: string) => {
    if (!a || !b || a.length !== b.length) return false;
    let r = 0;
    for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return r === 0;
  };
  return eq(bearer, serviceKey) || (cronSecret !== "" && eq(cronHeader, cronSecret));
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);
  if (!isServerCaller(req)) return json({ ok: false, error: "Forbidden" }, 403);

  let body: { userId?: string } = {};
  try {
    body = await req.json();
  } catch {
    body = {};
  }

  const client = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  try {
    const results = body.userId
      ? [await purgeAccount(client, body.userId)]
      : await purgeDueAccounts(client);
    const deleted = results.filter((r) => r.ok).length;
    console.log(`[delete-account] ${deleted}/${results.length} compte(s) supprimé(s)`);
    for (const r of results.filter((r) => !r.ok)) {
      console.warn(`[delete-account] ${r.userId} non supprimé : ${r.error}`);
    }
    return json({ ok: true, deleted, results });
  } catch (e) {
    console.error("[delete-account] exception", e);
    return json({ ok: false, error: String(e) }, 500);
  }
});
