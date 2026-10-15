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

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
// Audit 15/10/2026 : plafond d'images par appel (coût Claude).
const MAX_SUBJECT_IMAGES = 20;
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
  } catch (_) { /* fallback */ }

  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) {
    try {
      return JSON.parse(fence[1].trim());
    } catch (_) { /* fallback */ }
  }

  // Extracteur robuste : trouve le PREMIER objet JSON équilibré.
  // Gère le cas où Claude ajoute du texte avant/après ou concatène 2 JSONs.
  const start = trimmed.indexOf("{");
  if (start >= 0) {
    let depth = 0;
    let inString = false;
    let escape = false;
    for (let i = start; i < trimmed.length; i++) {
      const ch = trimmed[i];
      if (escape) { escape = false; continue; }
      if (ch === "\\") { escape = true; continue; }
      if (ch === '"') { inString = !inString; continue; }
      if (inString) continue;
      if (ch === "{") depth++;
      else if (ch === "}") {
        depth--;
        if (depth === 0) {
          const candidate = trimmed.substring(start, i + 1);
          try {
            return JSON.parse(candidate);
          } catch (e) {
            throw new Error(
              `Premier objet JSON invalide à la position ${start}: ` +
                `${(e as Error).message}. Extrait : ${candidate.substring(0, 200)}`,
            );
          }
        }
      }
    }
  }

  throw new Error(`Aucun JSON détecté dans la réponse : ${trimmed.substring(0, 300)}`);
}

const SYSTEM_PROMPT = `Tu es un assistant pédagogique expert en analyse de sujets d'examen.
Tu examines les photos d'un sujet d'examen et en extrais la structure complète en JSON.

Règles ABSOLUES :
- Lis attentivement le texte des images (imprimé OU manuscrit)
- Conserve EXACTEMENT le texte de chaque énoncé : équations, symboles, formules, données chiffrées
- Détecte les exercices (Exercice 1, Question 1, etc.) et leurs sous-questions (a, b, c, 1°, 2°…)
- Extrais les barèmes : "/2", "(3 pts)", "sur 4", "5 points", etc.
- Si pas de barème explicite pour un exercice : mets points = 0
- Les photos de tableau noir, manuscrites, ou floues mais lisibles doivent être traitées normalement
- Ne refuse pas une image qui contient un sujet d'examen, même si la qualité est moyenne

⚠️ FORMAT DE SORTIE — ULTRA STRICT :
- Tu retournes UN SEUL objet JSON et RIEN d'autre
- AUCUN texte avant le { d'ouverture
- AUCUN texte après le } de fermeture
- AUCUN markdown, AUCUN bloc \`\`\`
- AUCUN deuxième objet JSON, AUCUNE explication
- Ta réponse complète DOIT commencer par { et finir par }
- Si tu n'es pas sûr, retourne {"questions": []} et c'est tout

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
  // Audit 15/10/2026 — la fonction n'exigeait que la clé publique (anon) :
  // n'importe qui pouvait utiliser Claude à nos frais avec des URLs
  // arbitraires. On exige désormais un utilisateur connecté, des images de
  // NOTRE bucket « subjects » déposées dans SON dossier, et un plafond.
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userRes } = await userClient.auth.getUser();
  const userId = userRes?.user?.id;
  if (!userId) {
    return new Response(JSON.stringify({ error: "Non authentifié." }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    const imageUrls: string[] = body.imageUrls ?? [];
    if (imageUrls.length === 0) {
      throw new Error("imageUrls est requis (au moins 1 URL).");
    }
    if (imageUrls.length > MAX_SUBJECT_IMAGES) {
      return new Response(
        JSON.stringify({ error: `Trop de pages (max ${MAX_SUBJECT_IMAGES}).` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    const ownPrefix =
      `${SUPABASE_URL.replace(/\/$/, "")}/storage/v1/object/public/subjects/${userId}/`;
    if (imageUrls.some((u) => typeof u !== "string" || !u.startsWith(ownPrefix))) {
      return new Response(
        JSON.stringify({ error: "Images invalides : utilisez l'import du sujet de l'application." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
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
