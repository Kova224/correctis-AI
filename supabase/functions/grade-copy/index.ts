// =============================================================================
// Edge Function : grade-copy  (Claude Vision uniquement)
// Input  : { copyId: string }
//
// Claude reçoit dans un même appel :
//   1. Les pages de la copie de l'élève (images)
//   2. Les documents du corrigé type / cours (images, si fournis)
//   3. La structure du sujet (texte)
//   → Il comprend l'écriture manuscrite, croise avec le corrigé, et note.
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

async function callClaude(
  systemPrompt: string,
  // deno-lint-ignore no-explicit-any
  content: any[],
  maxTokens = 4096,
  temperature = 0.15,
): Promise<string> {
  if (!ANTHROPIC_API_KEY) {
    throw new Error("ANTHROPIC_API_KEY manquant (Supabase secrets).");
  }
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: maxTokens,
      temperature,
      system: systemPrompt,
      messages: [{ role: "user", content }],
    }),
  });
  if (!res.ok) {
    throw new Error(`Anthropic ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  return data?.content?.[0]?.text ?? "";
}

// deno-lint-ignore no-explicit-any
function extractJson(rawText: string): any {
  const trimmed = rawText.trim();
  try {
    return JSON.parse(trimmed);
  } catch (_) {
    const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fence) return JSON.parse(fence[1].trim());
    const s = trimmed.indexOf("{");
    const e = trimmed.lastIndexOf("}");
    if (s >= 0 && e > s) return JSON.parse(trimmed.substring(s, e + 1));
    throw new Error(`Réponse non-JSON: ${trimmed.substring(0, 200)}`);
  }
}

const SYSTEM_PROMPT =
  `Tu es un correcteur expert, juste et bienveillant. Tu corriges des copies d'élèves
en regardant leurs photos (écriture manuscrite incluse) et en t'appuyant sur le corrigé
ou le cours fourni.

Règles ABSOLUES :
- Lis attentivement la copie de l'élève (écriture manuscrite, schémas, calculs)
- Croise avec le corrigé type / le cours fourni pour évaluer l'exactitude
- Note STRICTEMENT selon le barème (n'attribue jamais plus que la note max)
- Notes en pas de 0,5 (0, 0,5, 1, 1,5, 2…)
- Commentaire bref pour chaque note (1-2 phrases, pédagogique)
- Commentaire général d'ensemble (2-3 phrases)
- Confiance entre 0 et 1 (0 = écriture illisible, 1 = très sûr)
- Sortie : UNIQUEMENT du JSON valide, AUCUN texte ni markdown autour

Format JSON :
{
  "grades": [
    { "leafId": "<uuid>", "score": 1.5, "comment": "Bonne démonstration mais erreur de calcul." },
    { "leafId": "<uuid>", "score": 2, "comment": "Excellent." }
  ],
  "generalComment": "Bonne copie, à consolider sur les démonstrations.",
  "confidence": 0.85
}`;

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
  try {
    const body = await req.json();
    const copyId: string = body.copyId ?? "";
    if (!copyId) throw new Error("copyId requis.");

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader) throw new Error("Non authentifié.");

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    // 1. Charge la copie
    const { data: copy, error: copyErr } = await supabase
      .from("student_copies")
      .select("*")
      .eq("id", copyId)
      .single();
    if (copyErr) throw new Error(`Copie introuvable : ${copyErr.message}`);

    // 2. Charge l'examen + questions + sous-questions
    const { data: exam, error: examErr } = await supabase
      .from("exams")
      .select("*, questions(*, sub_questions(*))")
      .eq("id", copy.exam_id)
      .single();
    if (examErr) throw new Error(`Examen introuvable : ${examErr.message}`);

    if (!copy.page_images || copy.page_images.length === 0) {
      throw new Error("Aucune page à corriger.");
    }

    // 3. Prépare la structure du sujet (texte pour le prompt)
    // deno-lint-ignore no-explicit-any
    const questionsForPrompt = (exam.questions ?? []).map((q: any) => {
      // deno-lint-ignore no-explicit-any
      const subs = (q.sub_questions ?? []).map((s: any) => ({
        leafId: s.id,
        label: s.label,
        statement: s.statement,
        maxPoints: Number(s.points) || 0,
      }));
      return subs.length > 0
        ? { label: q.label, statement: q.statement, subQuestions: subs }
        : {
          label: q.label,
          statement: q.statement,
          leafId: q.id,
          maxPoints: Number(q.points) || 0,
        };
    });

    // 4. Récupère le corrigé type / cours
    const correctionSource = exam.correction_source ?? {};
    const correctionType: string = correctionSource.type ?? "";
    const correctionDocs: string[] = correctionSource.documentPaths ?? [];
    const correctionText: string = correctionSource.generatedContent ?? "";

    let sourceLabel = "Aucun corrigé fourni — utilise tes connaissances générales.";
    if (correctionType === "answerKey") {
      sourceLabel =
        "Le professeur a fourni un CORRIGÉ TYPE (voir les images après celles de la copie). Compare strictement les réponses de l'élève à ce corrigé.";
    } else if (correctionType === "course") {
      sourceLabel =
        "Le professeur a fourni un COURS DE RÉFÉRENCE (voir les images après celles de la copie). Évalue la copie selon les notions du cours.";
    } else if (correctionType === "aiGenerated" && correctionText) {
      sourceLabel = `CORRIGÉ TYPE VALIDÉ PAR LE PROFESSEUR :\n${correctionText}`;
    }

    // 5. Construit le contenu multi-images pour Claude
    // deno-lint-ignore no-explicit-any
    const content: any[] = [];

    // a) Copie de l'élève
    content.push({
      type: "text",
      text:
        `Voici les ${copy.page_images.length} page(s) de la copie de l'élève "${copy.student_name}" :`,
    });
    for (const url of copy.page_images) {
      content.push({ type: "image", source: { type: "url", url } });
    }

    // b) Documents du corrigé ou cours (si images fournies)
    if (
      (correctionType === "answerKey" || correctionType === "course") &&
      correctionDocs.length > 0
    ) {
      content.push({
        type: "text",
        text:
          `Voici les ${correctionDocs.length} page(s) du ${
            correctionType === "answerKey" ? "corrigé type" : "cours"
          } fourni par le professeur :`,
      });
      for (const url of correctionDocs) {
        content.push({ type: "image", source: { type: "url", url } });
      }
    }

    // c) Structure du sujet + instructions
    content.push({
      type: "text",
      text: `Structure du sujet (barème officiel) :

${JSON.stringify(questionsForPrompt, null, 2)}

Source de correction :
${sourceLabel}

Note chaque leaf (question simple ou sous-question) avec son leafId exact tel que fourni.
Retourne UNIQUEMENT le JSON, sans texte ni markdown.`,
    });

    // 6. Appelle Claude
    const claudeRaw = await callClaude(SYSTEM_PROMPT, content, 3072, 0.15);
    const parsed = extractJson(claudeRaw);
    if (!parsed?.grades || !Array.isArray(parsed.grades)) {
      throw new Error("Format JSON invalide retourné par Claude.");
    }

    // 7. Met à jour la copie
    await supabase
      .from("student_copies")
      .update({
        status: "graded",
        general_comment: parsed.generalComment ?? "",
        confidence: Math.max(0, Math.min(1, parsed.confidence ?? 0.7)),
        graded_at: new Date().toISOString(),
      })
      .eq("id", copyId);

    // 8. Remplace les notes
    await supabase.from("question_grades").delete().eq("copy_id", copyId);
    if (parsed.grades.length > 0) {
      // deno-lint-ignore no-explicit-any
      const rows = parsed.grades.map((g: any) => ({
        copy_id: copyId,
        leaf_id: g.leafId,
        score: Number(g.score) || 0,
        comment: g.comment ?? "",
      }));
      await supabase.from("question_grades").insert(rows);
    }

    return new Response(JSON.stringify(parsed), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
