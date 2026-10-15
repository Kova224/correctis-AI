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
