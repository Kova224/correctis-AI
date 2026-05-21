// Helpers partagés pour appeler Google Cloud Vision et Anthropic Claude.

const VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const CLAUDE_MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-haiku-4-5-20251001";

// ---------------------------------------------------------------------------
// Google Cloud Vision : OCR sur une image (URL HTTP/HTTPS)
// ---------------------------------------------------------------------------
export async function ocrImageFromUrl(imageUrl: string): Promise<string> {
  if (!VISION_API_KEY) {
    throw new Error("GOOGLE_VISION_API_KEY manquant (Supabase secrets).");
  }
  const endpoint = `https://vision.googleapis.com/v1/images:annotate?key=${VISION_API_KEY}`;
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
    const errText = await res.text();
    throw new Error(`Vision API ${res.status}: ${errText}`);
  }
  const data = await res.json();
  const text = data?.responses?.[0]?.fullTextAnnotation?.text ?? "";
  return text;
}

// Concatène l'OCR de plusieurs pages (séparateur de page explicite).
export async function ocrMultipleImages(urls: string[]): Promise<string> {
  const texts: string[] = [];
  for (let i = 0; i < urls.length; i++) {
    const text = await ocrImageFromUrl(urls[i]);
    texts.push(`--- PAGE ${i + 1} ---\n${text}`);
  }
  return texts.join("\n\n");
}

// ---------------------------------------------------------------------------
// Anthropic Claude : appel de complétion avec system prompt + user prompt
// ---------------------------------------------------------------------------
export async function callClaude(params: {
  system: string;
  user: string;
  maxTokens?: number;
  temperature?: number;
}): Promise<string> {
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
      max_tokens: params.maxTokens ?? 4096,
      temperature: params.temperature ?? 0.2,
      system: params.system,
      messages: [{ role: "user", content: params.user }],
    }),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Anthropic ${res.status}: ${errText}`);
  }
  const data = await res.json();
  const text = data?.content?.[0]?.text ?? "";
  return text;
}

// Extrait un bloc JSON depuis une réponse texte de Claude (qui peut contenir
// du texte autour). Tente d'abord un parse direct, puis cherche entre ```json ```.
export function extractJson<T = unknown>(rawText: string): T {
  // 1. Tente parse direct
  const trimmed = rawText.trim();
  try {
    return JSON.parse(trimmed) as T;
  } catch (_) {
    // 2. Cherche un bloc ```json ... ```
    const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fenceMatch) {
      return JSON.parse(fenceMatch[1].trim()) as T;
    }
    // 3. Cherche le premier `{` ou `[` jusqu'au dernier `}` ou `]`
    const objStart = trimmed.indexOf("{");
    const objEnd = trimmed.lastIndexOf("}");
    if (objStart >= 0 && objEnd > objStart) {
      return JSON.parse(trimmed.substring(objStart, objEnd + 1)) as T;
    }
    throw new Error(`Réponse non-JSON de Claude: ${trimmed.substring(0, 200)}`);
  }
}
