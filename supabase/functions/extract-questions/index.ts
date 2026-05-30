// =============================================================================
// Edge Function : extract-questions  (Claude Vision uniquement)
// Input  : { imageUrls: string[], language?: string, examType?: string }
// Output : { questions: [...] }
//
// Claude voit les images du sujet et retourne directement la structure JSON.
// Aucune dépendance à Google Vision.
// =============================================================================

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const CLAUDE_MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-haiku-4-5-20251001";

// deno-lint-ignore no-explicit-any
async function callClaudeWithImages(
  systemPrompt: string,
  userPrompt: string,
  imageUrls: string[],
  maxTokens = 4096,
  temperature = 0.1,
): Promise<string> {
  if (!ANTHROPIC_API_KEY) {
    throw new Error("ANTHROPIC_API_KEY manquant (Supabase secrets).");
  }
  // deno-lint-ignore no-explicit-any
  const content: any[] = imageUrls.map((url) => ({
    type: "image",
    source: { type: "url", url },
  }));
  content.push({ type: "text", text: userPrompt });

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

const SYSTEM_PROMPT = `Tu es un assistant pédagogique expert en analyse de sujets d'examen.
Tu examines les photos d'un sujet d'examen et en extrais la structure complète en JSON.

Règles ABSOLUES :
- Lis attentivement le texte des images (imprimé OU manuscrit)
- Conserve EXACTEMENT le texte de chaque énoncé : équations, symboles, formules, données chiffrées
- Détecte les exercices (Exercice 1, Question 1, etc.) et leurs sous-questions (a, b, c, 1°, 2°…)
- Extrais les barèmes : "/2", "(3 pts)", "sur 4", "5 points", etc.
- Si pas de barème explicite pour un exercice : mets points = 0
- Sortie : UNIQUEMENT du JSON valide, AUCUN texte ni markdown autour

Format JSON :
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
      "statement": "Énoncé simple",
      "points": 3,
      "subQuestions": []
    }
  ]
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
    const imageUrls: string[] = body.imageUrls ?? [];
    if (imageUrls.length === 0) {
      throw new Error("imageUrls est requis (au moins 1 URL).");
    }

    const userPrompt =
      `Langue de l'examen : ${body.language ?? "fr"}
Type d'examen : ${body.examType ?? "general"}

Regarde les ${imageUrls.length} page(s) du sujet ci-dessus et retourne UNIQUEMENT le JSON structuré.`;

    const claudeRaw = await callClaudeWithImages(
      SYSTEM_PROMPT,
      userPrompt,
      imageUrls,
      4096,
      0.1,
    );
    const parsed = extractJson(claudeRaw);
    if (!parsed?.questions || !Array.isArray(parsed.questions)) {
      throw new Error("Format JSON invalide retourné par Claude.");
    }

    return new Response(JSON.stringify({ questions: parsed.questions }), {
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
