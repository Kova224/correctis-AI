// =============================================================================
// Edge Function : grade-copy  (VERSION AUTONOME)
// Input  : { copyId: string }
// Output : { grades: [...], generalComment: string, confidence: number }
//
// Pipeline : charge copie+examen → Vision OCR → Claude (notation) → update DB
//
// Déployable par copier-coller dans le dashboard Supabase.
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// --- CORS --------------------------------------------------------------------
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// --- Secrets -----------------------------------------------------------------
const VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const CLAUDE_MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-haiku-4-5-20251001";

// --- Google Cloud Vision -----------------------------------------------------
async function ocrImageFromUrl(imageUrl: string): Promise<string> {
  if (!VISION_API_KEY) {
    throw new Error("GOOGLE_VISION_API_KEY manquant (Supabase secrets).");
  }
  const endpoint =
    `https://vision.googleapis.com/v1/images:annotate?key=${VISION_API_KEY}`;
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      requests: [
        {
          image: { source: { imageUri: imageUrl } },
          features: [{ type: "DOCUMENT_TEXT_DETECTION", maxResults: 1 }],
          imageContext: { languageHints: ["fr", "en", "ar"] },
        },
      ],
    }),
  });
  if (!res.ok) {
    throw new Error(`Vision API ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  return data?.responses?.[0]?.fullTextAnnotation?.text ?? "";
}

async function ocrMultipleImages(urls: string[]): Promise<string> {
  const texts: string[] = [];
  for (let i = 0; i < urls.length; i++) {
    texts.push(`--- PAGE ${i + 1} ---\n${await ocrImageFromUrl(urls[i])}`);
  }
  return texts.join("\n\n");
}

// --- Anthropic Claude --------------------------------------------------------
async function callClaude(
  system: string,
  user: string,
  maxTokens = 3072,
  temperature = 0.2,
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
      system,
      messages: [{ role: "user", content: user }],
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

// --- Prompt système ----------------------------------------------------------
const SYSTEM_PROMPT =
  `Tu es un correcteur expert et juste. Tu corriges des copies d'élèves selon un barème précis.

Règles ABSOLUES :
- Note chaque question/sous-question STRICTEMENT selon le barème fourni
- N'attribue jamais plus de points que le barème n'autorise
- Les notes doivent être en pas de 0,5 (0, 0,5, 1, 1,5, 2…)
- Commente brièvement chaque note (1-2 phrases max, pédagogique et bienveillant)
- Donne un commentaire général d'ensemble en 2-3 phrases
- Indique ton niveau de confiance entre 0 et 1 (0 = très incertain, 1 = très sûr)
- Sortie : UNIQUEMENT du JSON valide, AUCUN texte ni markdown autour

Format JSON attendu :
{
  "grades": [
    { "leafId": "<uuid>", "score": 1.5, "comment": "Bonne démonstration mais erreur de calcul." },
    { "leafId": "<uuid>", "score": 2, "comment": "Excellent." }
  ],
  "generalComment": "Bonne copie dans l'ensemble.",
  "confidence": 0.85
}`;

// --- Handler -----------------------------------------------------------------
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

    // 3. OCR de la copie
    const studentText = await ocrMultipleImages(copy.page_images);
    if (!studentText.trim()) {
      throw new Error("Aucun texte détecté sur la copie.");
    }

    // 4. Prépare la structure du sujet pour le prompt
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

    const correctionSource = exam.correction_source
      ? JSON.stringify(exam.correction_source)
      : "Aucun corrigé fourni — utilise tes connaissances générales.";

    const userPrompt = `Voici le sujet d'examen structuré :

${JSON.stringify(questionsForPrompt, null, 2)}

Source de correction du professeur :
${correctionSource}

Voici l'OCR de la copie de l'élève "${copy.student_name}" :

${studentText}

Note chaque leaf (question simple ou sous-question) avec son leafId exact.
Retourne UNIQUEMENT le JSON, sans texte ni markdown.`;

    // 5. Correction par Claude
    const claudeRaw = await callClaude(SYSTEM_PROMPT, userPrompt, 3072, 0.2);
    const parsed = extractJson(claudeRaw);
    if (!parsed?.grades || !Array.isArray(parsed.grades)) {
      throw new Error("Format JSON invalide retourné par Claude.");
    }

    // 6. Met à jour la copie
    await supabase
      .from("student_copies")
      .update({
        status: "graded",
        general_comment: parsed.generalComment ?? "",
        confidence: Math.max(0, Math.min(1, parsed.confidence ?? 0.7)),
        graded_at: new Date().toISOString(),
      })
      .eq("id", copyId);

    // 7. Remplace les notes
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
