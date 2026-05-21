// =============================================================================
// Edge Function : extract-questions  (VERSION AUTONOME)
// Input  : { imageUrls: string[], language?: string, examType?: string }
// Output : { questions: [...], rawOcr: string }
//
// Pipeline : Google Cloud Vision OCR  →  Claude Haiku (structuration JSON)
//
// Déployable par copier-coller dans le dashboard Supabase (aucun import local).
// =============================================================================

// --- CORS --------------------------------------------------------------------
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// --- Secrets (configurés dans Supabase → Edge Functions → Secrets) ----------
const VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const CLAUDE_MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-haiku-4-5-20251001";

// --- Google Cloud Vision : OCR d'une image ----------------------------------
async function ocrImageFromUrl(imageUrl: string): Promise<string> {
  if (!VISION_API_KEY) {
    throw new Error("GOOGLE_VISION_API_KEY manquant (Supabase secrets).");
  }
  const endpoint =
    `https://vision.googleapis.com/v1/images:annotate?key=${VISION_API_KEY}`;
  const body = {
    requests: [
      {
        image: { source: { imageUri: imageUrl } },
        features: [{ type: "DOCUMENT_TEXT_DETECTION", maxResults: 1 }],
        imageContext: { languageHints: ["fr", "en", "ar"] },
      },
    ],
  };
  const res = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
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
  maxTokens = 4096,
  temperature = 0.1,
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
  `Tu es un assistant pédagogique spécialisé dans l'analyse de sujets d'examen.
Ton rôle : transformer du texte brut (issu de l'OCR d'un sujet d'examen) en structure JSON propre.

Règles ABSOLUES :
- Conserve EXACTEMENT le texte de l'énoncé (équations, symboles, formules) — ne reformule pas
- Détecte les exercices et leurs sous-questions (a, b, c, 1°, 2°, etc.)
- Extrais les barèmes : "/2", "(3 pts)", "sur 4", etc.
- Si un exercice n'a pas de barème explicite, mets points = 0
- Sortie : UNIQUEMENT du JSON valide, AUCUN texte autour, AUCUN markdown

Format JSON attendu :
{
  "questions": [
    {
      "label": "Exercice 1",
      "statement": "Énoncé complet de l'exercice...",
      "points": 0,
      "subQuestions": [
        { "label": "a)", "statement": "...", "points": 1.5 },
        { "label": "b)", "statement": "...", "points": 2 }
      ]
    },
    {
      "label": "Question 2",
      "statement": "Énoncé d'une question simple",
      "points": 3,
      "subQuestions": []
    }
  ]
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
    const imageUrls: string[] = body.imageUrls ?? [];
    if (imageUrls.length === 0) {
      throw new Error("imageUrls est requis (au moins 1 URL).");
    }

    const rawOcr = await ocrMultipleImages(imageUrls);
    if (!rawOcr.trim()) throw new Error("Aucun texte détecté sur les images.");

    const userPrompt =
      `Langue de l'examen : ${body.language ?? "fr"}
Type d'examen : ${body.examType ?? "general"}

Texte OCR du sujet (peut contenir des erreurs de reconnaissance) :

${rawOcr}

Retourne UNIQUEMENT le JSON structuré, sans texte ni markdown autour.`;

    const claudeRaw = await callClaude(SYSTEM_PROMPT, userPrompt, 4096, 0.1);
    const parsed = extractJson(claudeRaw);
    if (!parsed?.questions || !Array.isArray(parsed.questions)) {
      throw new Error("Format JSON invalide retourné par Claude.");
    }

    return new Response(
      JSON.stringify({ questions: parsed.questions, rawOcr }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
