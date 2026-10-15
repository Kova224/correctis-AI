// =============================================================================
// Nettoyage des images orphelines du bucket "copies"
// =============================================================================
// Supprime les images du Storage qui n'ont plus de ligne correspondante dans
// student_copies, OU dont la copie est gradée + lockée depuis plus de N jours.
//
// À appeler manuellement quand le Storage est plein, OU à planifier en CRON
// quotidien pour éviter l'accumulation.
//
// Body optionnel (POST JSON) :
//   { "dry_run": true }   → ne supprime rien, retourne juste le compte
//   { "keep_days": 7 }    → conserve les copies gradées lockées depuis < N jours
//   { "all_graded": true } → supprime aussi les graded même non lockées
//
// Retourne :
//   { dry_run, scanned, deleted, freed_mb, kept }
// =============================================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0';

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
  if (!isServerCaller(req)) {
    return new Response(JSON.stringify({ error: 'Forbidden' }), {
      status: 403,
      headers: { 'content-type': 'application/json' },
    });
  }
  let body: any = {};
  if (req.method === 'POST') {
    try {
      body = await req.json();
    } catch {
      body = {};
    }
  }
  const dryRun = body.dry_run === true;
  const keepDays = typeof body.keep_days === 'number' ? body.keep_days : 7;
  const allGraded = body.all_graded === true;

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // ── 1. Charge tous les copy_id existants (encore en DB) ──
  // Audit 15/10/2026 : PostgREST plafonne à 1000 lignes par requête. Sans
  // pagination, au-delà de 1000 copies les images des copies non chargées
  // étaient prises pour des « orphelines »… et SUPPRIMÉES. On pagine.
  const existingCopies: { id: string; status: string; locked_at: string | null }[] = [];
  for (let from = 0; ; from += 1000) {
    const { data: page, error: copiesErr } = await admin
      .from('student_copies')
      .select('id, status, locked_at')
      .order('id', { ascending: true })
      .range(from, from + 999);
    if (copiesErr) {
      return new Response(
        JSON.stringify({ error: copiesErr.message }),
        { status: 500, headers: { 'content-type': 'application/json' } },
      );
    }
    existingCopies.push(...((page ?? []) as any[]));
    if (!page || page.length < 1000) break;
  }

  // Map id → { status, locked_at }
  const copyMap = new Map<string, { status: string; lockedAt: string | null }>();
  for (const c of existingCopies ?? []) {
    copyMap.set(c.id as string, {
      status: c.status as string,
      lockedAt: c.locked_at as string | null,
    });
  }

  // ── 2. Liste tous les objets du bucket "copies" (pagination) ──
  // L'API Supabase Storage limite à 1000 objets par appel.
  let offset = 0;
  const pageSize = 1000;
  let scanned = 0;
  let deleted = 0;
  let freedBytes = 0;
  const toDelete: string[] = [];
  const reasons: Record<string, number> = {
    orphan: 0,
    graded_locked: 0,
    all_graded: 0,
  };

  // On utilise l'API Storage admin via service_role
  while (true) {
    const { data: objects, error: listErr } = await admin.storage
      .from('copies')
      .list('', {
        limit: pageSize,
        offset,
        sortBy: { column: 'name', order: 'asc' },
      });
    if (listErr) {
      return new Response(
        JSON.stringify({ error: listErr.message }),
        { status: 500, headers: { 'content-type': 'application/json' } },
      );
    }
    if (!objects || objects.length === 0) break;

    // ⚠️ list('') ne descend pas dans les sous-dossiers automatiquement.
    // Pour parcourir tout le bucket, il faudrait lister chaque user_id puis
    // chaque copy_id. Pour simplifier, on fait un parcours direct par les
    // copy_id connus.
    break;
  }

  // ── 2bis. Approche alternative : on liste storage.objects via SQL ──
  // (en lecture seule c'est autorisé, c'est juste DELETE qui est bloqué).
  const { data: storageObjs, error: storageErr } = await admin
    .from('objects' as any)
    .select('name, metadata')
    .eq('bucket_id', 'copies')
    .limit(50000); // on récupère tout pour analyse
  // ⚠️ accès via .from('objects') marche uniquement si on est dans le schéma
  // storage. Si erreur, on passe par RPC.

  let allObjects: { name: string; metadata: any }[] = [];
  if (!storageErr && storageObjs) {
    allObjects = storageObjs as any[];
  } else {
    // Fallback : RPC SQL custom (à créer si besoin)
    return new Response(
      JSON.stringify({
        error:
          'Impossible de lister storage.objects depuis Edge Function. ' +
          'Utilisez l\'UI Storage manuellement ou créez une RPC list_storage_copies.',
        hint: storageErr?.message,
      }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  // ── 3. Décide pour chaque fichier ──
  for (const obj of allObjects) {
    scanned++;
    const fileName = obj.name as string;
    const fileSize = obj.metadata?.size ?? 0;

    // Le nom du fichier contient le copy_id (ex: "user_abc/copy_xyz/page1.jpg")
    // On cherche un UUID dans le path.
    const uuidMatch = fileName.match(
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
    );
    if (!uuidMatch) continue;

    let shouldDelete = false;
    let reason = '';

    // Cherche dans les UUID extraits lequel correspond à une copie existante
    let foundCopy: { status: string; lockedAt: string | null } | undefined;
    for (const uuid of uuidMatch) {
      const c = copyMap.get(uuid);
      if (c) {
        foundCopy = c;
        break;
      }
    }

    if (!foundCopy) {
      // Orphelin : la copie n'existe plus en DB
      shouldDelete = true;
      reason = 'orphan';
    } else if (allGraded && foundCopy.status === 'graded') {
      shouldDelete = true;
      reason = 'all_graded';
    } else if (
      foundCopy.status === 'graded' &&
      foundCopy.lockedAt &&
      new Date(foundCopy.lockedAt).getTime() <
        Date.now() - keepDays * 86400000
    ) {
      shouldDelete = true;
      reason = 'graded_locked';
    }

    if (shouldDelete) {
      toDelete.push(fileName);
      freedBytes += fileSize;
      reasons[reason] = (reasons[reason] || 0) + 1;
    }
  }

  // ── 4. Supprime via l'API Storage (sauf en dry_run) ──
  if (!dryRun && toDelete.length > 0) {
    // Supprimer par batch de 100 (limite de l'API Storage)
    for (let i = 0; i < toDelete.length; i += 100) {
      const batch = toDelete.slice(i, i + 100);
      const { error: delErr } = await admin.storage
        .from('copies')
        .remove(batch);
      if (delErr) {
        console.error('[cleanup] batch delete error', delErr);
      } else {
        deleted += batch.length;
      }
    }
  }

  return new Response(
    JSON.stringify({
      dry_run: dryRun,
      scanned,
      to_delete: toDelete.length,
      deleted,
      freed_mb: (freedBytes / 1024 / 1024).toFixed(2),
      kept: scanned - toDelete.length,
      breakdown: reasons,
    }),
    { status: 200, headers: { 'content-type': 'application/json' } },
  );
});
