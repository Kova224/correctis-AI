// =============================================================================
// Edge Function : generate-answer-key  (option C « Génération IA » du corrigé)
// =============================================================================
// Audit 15/10/2026 : l'option C était simulée côté app (corrigé vide « à
// compléter »). Cette fonction produit un vrai corrigé type avec Claude, à
// partir du sujet (photos) et du barème validé par le prof. Le prof relit et
// VALIDE le texte avant toute correction (règle inchangée).
//
// Input  : { examId: string }
// Output : { content: string }   (markdown, une section par question)
//
// Sécurité / coût :
//   - utilisateur connecté, propriétaire de l'examen ;
//   - images du sujet limitées à NOTRE bucket « subjects » (20 max) ;
//   - 5 générations max par examen et par 24 h (table answer_key_generations).
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const CLAUDE_MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-haiku-4-5-20251001";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const MAX_SUBJECT_IMAGES = 20;
const MAX_GENERATIONS_PER_DAY = 5;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const SYSTEM_PROMPT = `Tu es un professeur expérimenté qui rédige le CORRIGÉ TYPE d'un examen,
destiné à servir de référence pour corriger des copies d'élèves.

Règles :
- Respecte EXACTEMENT la liste des questions et le barème fournis (mêmes libellés, mêmes points).
- Pour chaque question (ou sous-question), donne :
  • la réponse attendue, complète et juste (calculs détaillés si besoin) ;
  • les éléments qui rapportent des points, avec leur répartition dans le barème ;
  • les erreurs fréquentes à ne pas accepter, si utile.
- Écris dans la langue de l'examen indiquée.
- Si une question est illisible ou ambiguë sur le sujet, dis-le en une ligne
  (« À vérifier par le professeur : … ») au lieu d'inventer.
- Format : Markdown simple. Un titre "### <libellé> (<points> pts)" par question,
  puis "- **<sous-question>** (<points> pts)" pour les sous-questions.
- Termine par la ligne : "— Corrigé généré par l'IA, à relire et valider par le professeur."`;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!ANTHROPIC_API_KEY) return json({ error: "ANTHROPIC_API_KEY manquant (secrets Supabase)." }, 500);

  // 1. Utilisateur connecté
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userRes } = await userClient.auth.getUser();
  const userId = userRes?.user?.id;
  if (!userId) return json({ error: "Non authentifié." }, 401);

  let body: { examId?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body JSON invalide" }, 400);
  }
  const examId = body.examId ?? "";
  if (!examId) return json({ error: "examId requis" }, 400);

  // 2. Examen du prof (RLS : seul le propriétaire le lit)
  const { data: exam, error: examErr } = await userClient
    .from("exams")
    .select("id, owner_id, title, class_name, total_points, language, exam_type, subject_images, questions(*, sub_questions(*))")
    .eq("id", examId)
    .maybeSingle();
  if (examErr || !exam || exam.owner_id !== userId) {
    return json({ error: "Examen introuvable." }, 404);
  }
  // deno-lint-ignore no-explicit-any
  const questions = ((exam.questions as any[]) ?? [])
    .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
  if (questions.length === 0) {
    return json({ error: "Validez d'abord les questions et le barème du sujet." }, 400);
  }

  // 3. Plafond d'usage
  const svc = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const since = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
  const { count } = await svc
    .from("answer_key_generations")
    .select("id", { count: "exact", head: true })
    .eq("exam_id", examId)
    .gte("created_at", since);
  if ((count ?? 0) >= MAX_GENERATIONS_PER_DAY) {
    return json({
      error: `Limite atteinte : ${MAX_GENERATIONS_PER_DAY} générations par examen et par 24 h. Modifiez le corrigé à la main ou réessayez demain.`,
      code: "GENERATION_LIMIT",
    }, 429);
  }

  // 4. Images du sujet (bucket public « subjects », dossier du prof)
  const subjectPrefix =
    `${SUPABASE_URL.replace(/\/$/, "")}/storage/v1/object/public/subjects/${userId}/`;
  const images = ((exam.subject_images as string[] | null) ?? [])
    .filter((u) => typeof u === "string" && u.startsWith(subjectPrefix))
    .filter((u) => /\.(jpe?g|png|webp|gif)(\?|$)/i.test(u))
    .slice(0, MAX_SUBJECT_IMAGES);

  // 5. Barème au format texte
  const lines: string[] = [];
  for (const q of questions) {
    lines.push(`${q.label} (${q.points ?? 0} pts) : ${q.statement ?? ""}`.trim());
    // deno-lint-ignore no-explicit-any
    const subs = ((q.sub_questions as any[]) ?? [])
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0));
    for (const sq of subs) {
      lines.push(`  - ${sq.label} (${sq.points ?? 0} pts) : ${sq.statement ?? ""}`.trim());
    }
  }
  const userPrompt =
    `Examen : ${exam.title ?? ""}${exam.class_name ? ` — classe ${exam.class_name}` : ""}
Langue : ${exam.language ?? "fr"} · Type : ${exam.exam_type ?? "general"} · Total : ${exam.total_points ?? 20} pts
${images.length > 0 ? `Les ${images.length} photo(s) du sujet sont jointes ci-dessus.` : "Aucune photo du sujet : base-toi sur les énoncés ci-dessous."}

Questions et barème validés par le professeur :
${lines.join("\n")}

Rédige le corrigé type complet.`;

  // deno-lint-ignore no-explicit-any
  const content: any[] = images.map((url) => ({
    type: "image",
    source: { type: "url", url },
  }));
  content.push({ type: "text", text: userPrompt });

  // Journalise AVANT l'appel (une tentative compte, même en cas d'échec IA)
  await svc.from("answer_key_generations").insert({ exam_id: examId, user_id: userId });

  try {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: CLAUDE_MODEL,
        max_tokens: 4096,
        temperature: 0.2,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content }],
      }),
    });
    if (!res.ok) {
      const errText = await res.text();
      console.error("[generate-answer-key] Anthropic", res.status, errText.slice(0, 300));
      return json({ error: `Service IA indisponible (${res.status}). Réessayez.` }, 502);
    }
    const data = await res.json();
    // deno-lint-ignore no-explicit-any
    const text = ((data?.content as any[]) ?? [])
      .filter((b) => b?.type === "text")
      .map((b) => b.text as string)
      .join("\n")
      .trim();
    if (!text) return json({ error: "Réponse vide de l'IA. Réessayez." }, 502);
    return json({ content: text });
  } catch (e) {
    console.error("[generate-answer-key] exception", String(e));
    return json({ error: "Service IA injoignable. Réessayez." }, 502);
  }
});
