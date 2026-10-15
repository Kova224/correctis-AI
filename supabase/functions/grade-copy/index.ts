// =============================================================================
// Edge Function : grade-copy  v6 — Protocole "Correcteur académique expert"
// =============================================================================
// Implémente le protocole formel envoyé par Michel Kova Bilivogui, 9 juin 2026.
//
//   PHASE A — Analyse du sujet (reconstruction du barème + vérification)
//   PHASE B — Lecture de la copie (indexation page → contenu)
//   PHASE C — Association réponse ↔ question (ordre quelconque)
//   PHASE D — Gatekeeper hors-sujet (2 niveaux : matière + énoncés précis)
//   PHASE E — Notation question-par-question (rapport détaillé)
//   PHASE F — Arithmétique stricte + test de cohérence
//
// v6 (juin 2026) : intégration des 10 étapes du correcteur expert avec
// rapport détaillé pour chaque question (réponse détectée, points obtenus,
// points manquants, justification).
//
// Le format de sortie demandé à l'IA est celui de Michel (correction_detaillee
// avec partie / question / bareme_question / note_attribuee / methode_utilisee
// / analyse_prof), enrichi du leafId pour permettre le mapping avec notre DB.
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

// Marqueurs magiques côté Flutter pour détecter les états spéciaux
const OFF_TOPIC_MARKER = "⛔ HORS-SUJET — ";
const ZONE_ILLISIBLE_MARKER = "[ZONE_ILLISIBLE] ";

async function callClaude(
  systemPrompt: string,
  // deno-lint-ignore no-explicit-any
  content: any[],
  maxTokens = 8192,
): Promise<string> {
  if (!ANTHROPIC_API_KEY) {
    throw new Error("ANTHROPIC_API_KEY manquant (Supabase secrets).");
  }
  // C4 — PROMPT CACHING (Anthropic ephemeral cache)
  // Deux breakpoints de cache pour maximiser les économies sur un batch de
  // copies d'un même examen :
  //   1. System prompt (~10k tokens du protocole correcteur — cache 1h)
  //   2. Le contenu fixe par examen (sujet officiel + corrigé + cours +
  //      barème JSON) est marqué avec cache_control sur son DERNIER bloc
  //      texte. Anthropic met en cache tout ce qui précède ce breakpoint.
  // La copie de l'élève et ses images viennent APRÈS le breakpoint, donc
  // ne sont pas cachées (unique par copie, normal).
  //
  // TTL 1h : les profs corrigent parfois une classe entière sur 20-40 min ;
  // le cache 5 min expirait entre copies → 1h couvre toute la séance.
  //
  // Économie attendue par copie (après la 1re) :
  //   - System prompt : ~10k tokens × (1 - 0.10) = ~9k tokens économisés
  //   - Contexte fixe : ~5-10k tokens × 0.90 économisés
  //   - Vitesse : lecture cache = 2-3× plus rapide
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "anthropic-beta": "extended-cache-ttl-2025-04-11",
    },
    body: JSON.stringify({
      model: CLAUDE_MODEL,
      max_tokens: maxTokens,
      temperature: 0,
      system: [
        {
          type: "text",
          text: systemPrompt,
          cache_control: { type: "ephemeral", ttl: "1h" },
        },
      ],
      messages: [{ role: "user", content }],
    }),
  });
  if (!res.ok) {
    throw new Error(`Anthropic ${res.status}: ${await res.text()}`);
  }
  const data = await res.json();
  // Log cache hits/misses (utile pour vérifier l'efficacité)
  const u = data?.usage;
  if (u) {
    console.log(
      `[grade-copy] tokens : in=${u.input_tokens} out=${u.output_tokens} ` +
        `cache_read=${u.cache_read_input_tokens ?? 0} ` +
        `cache_write=${u.cache_creation_input_tokens ?? 0}`,
    );
  }
  return data?.content?.[0]?.text ?? "";
}

// deno-lint-ignore no-explicit-any
function extractJson(rawText: string): any {
  const trimmed = rawText.trim();

  // Tentative 1 : parse direct
  try {
    return JSON.parse(trimmed);
  } catch (_) { /* fallback */ }

  // Tentative 2 : à l'intérieur d'un bloc ```json...```
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fence) {
    try {
      return JSON.parse(fence[1].trim());
    } catch (_) { /* fallback */ }
  }

  // Tentative 3 : trouve le PREMIER objet JSON équilibré en suivant les
  // accolades caractère par caractère (gère le cas où Claude ajoute du
  // texte AVANT ou APRÈS le JSON, ou concatène plusieurs objets).
  // C'est l'extracteur le plus robuste — il s'arrête au premier objet complet.
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
          // On a trouvé la fin du premier objet équilibré
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

// -----------------------------------------------------------------------------
// PROMPT SYSTÈME — Protocole formel du correcteur académique expert.
// (Michel Kova Bilivogui, version 9 juin 2026)
// -----------------------------------------------------------------------------
const SYSTEM_PROMPT =
  `Vous êtes le moteur d'évaluation IA central et multimodal de l'application
"EduCorrect / Correctis". Vous incarnez un CORRECTEUR ACADÉMIQUE EXPERT —
rigoureux, juste, méthodique. Vous appliquez le protocole formel suivant
SANS DÉVIATION.

═══════════════════════════════════════════════════════════════
PROTOCOLE DU CORRECTEUR EXPERT — 10 ÉTAPES OBLIGATOIRES
═══════════════════════════════════════════════════════════════

ÉTAPE 1 — ANALYSE DU SUJET
  Analysez d'abord le [SUJET OFFICIEL] et reconstruisez précisément sa
  structure complète : questions, sous-questions, consignes et barèmes.
  Le barème vous est fourni en structure JSON ci-dessous + en image
  originale. Confrontez les deux pour vérifier la cohérence.

ÉTAPE 2 — VÉRIFICATION DU SUJET
  Vérifiez que chaque élément du sujet a été identifié correctement avant
  de commencer la correction. Si un élément du barème JSON ne correspond
  pas clairement à un élément des images du sujet, signalez-le mais
  poursuivez selon le JSON fourni (qui fait foi).

ÉTAPE 3 — LECTURE DE LA COPIE
  Analysez ensuite la copie de l'élève. LISEZ TOUTES les pages d'abord.
  L'ordre des pages est QUELCONQUE — ne tirez aucune conclusion de cet
  ordre. Construisez mentalement un INDEX :
    Page n°1 (visuelle) → contient les blocs : [Q2 partie a), Q3 complet]
    Page n°2 (visuelle) → contient les blocs : [Q1 complet, début Q4]
    etc.

ÉTAPE 4 — NE JAMAIS SUPPOSER L'ORDRE
  Ne supposez JAMAIS que les réponses suivent l'ordre des questions du
  sujet. Une copie peut traiter Q3 d'abord puis Q1. La même copie
  scannée dans l'ordre inverse DOIT recevoir EXACTEMENT la même note.

ÉTAPE 5 — ASSOCIATION RÉPONSE ↔ QUESTION
  Pour CHAQUE réponse trouvée dans la copie :
    • Identifier la question correspondante (via labels "1)", "Q2",
      "Exercice 3", "a)", "b)", etc. écrits PAR L'ÉLÈVE)
    • Vérifier si la réponse est pertinente ou hors-sujet
    • Associer la réponse à la BONNE question, même si elle apparaît
      ailleurs dans la copie ou éclatée sur plusieurs pages
    • Évaluer uniquement les éléments pertinents

ÉTAPE 6 — GATEKEEPER HORS-SUJET (DEUX NIVEAUX)
  Si une réponse est totalement hors-sujet, signalez-le explicitement.
  La copie globale est HORS_SUJET dans deux cas :

  6.1 Matière incorrecte :
    Sujet maths + copie chimie → HORS_SUJET global
    Sujet français + copie histoire → HORS_SUJET global

  6.2 Même matière mais ÉNONCÉS différents :
    Sujet "équations différentielles" + copie "dérivées simples" →
    HORS_SUJET global, l'élève traite d'autres exercices

  En cas de HORS_SUJET global :
    • statut_conformite = "HORS_SUJET"
    • note_finale = "00 / <bareme_total>"
    • Toutes les leafIds avec note_attribuee = 0 et
      methode_utilisee = "NON_TRAITEE"
    • verification_initiale explique précisément l'écart constaté

ÉTAPE 7 — CORRECTION DE TOUTES LES QUESTIONS
  Corrigez OBLIGATOIREMENT toutes les questions et sous-questions du
  sujet, MÊME si l'élève n'a rien écrit pour certaines (note = 0,
  methode_utilisee = "NON_TRAITEE"). Aucun leafId du barème ne doit
  manquer du tableau correction_detaillee.

ÉTAPE 8 — RAPPORT DÉTAILLÉ PAR QUESTION
  Pour chaque leafId, générez un rapport contenant :
    • partie + question (label) — identification de la question
    • bareme_question — points maximums de cette question
    • note_attribuee — points obtenus par l'élève
    • points_manquants — différence (bareme_question - note_attribuee)
    • reponse_detectee — résumé court (1-2 phrases) de ce que l'élève
      a écrit pour cette question. Si rien : "Aucune réponse détectée."
    • methode_utilisee — l'une des valeurs : "CONFORME AU CORRIGÉ",
      "ALTERNATIVE VALIDE", "ERRONÉE", "NON_TRAITEE", "ZONE_INCOMPREHENSIBLE"
    • justification — phrase courte justifiant la note (ce qui a été
      comptabilisé, ce qui manquait par rapport au corrigé/cours)
    • analyse_prof — synthèse pédagogique 1-2 phrases destinée au prof

ÉTAPE 9 — AUCUN EXERCICE OMIS
  Aucun exercice ni sous-question ne doit être omis dans le rapport
  final, même si aucune réponse n'est présente. Les questions non
  traitées apparaissent avec note 0 et la mention "Aucune réponse
  détectée."

ÉTAPE 10 — GESTION DE L'AMBIGUÏTÉ
  En cas d'ambiguïté dans le sujet ou dans la copie :
    • Ne JAMAIS inventer ni supposer une réponse
    • Marquer methode_utilisee = "ZONE_INCOMPREHENSIBLE"
    • analyse_prof commence par "[ZONE_ILLISIBLE] : ..."
    • note_attribuee = 0 jusqu'à confirmation prof

═══════════════════════════════════════════════════════════════
RÈGLES TRANSVERSALES (s'appliquent à toutes les étapes)
═══════════════════════════════════════════════════════════════

R1. CONSTANCE & DÉTERMINISME
  • Notes en pas de 0,5 (0 ; 0,5 ; 1 ; 1,5 ; …)
  • Jamais au-dessus du barème de la question
  • Mêmes critères pour toutes les questions et toutes les copies
  • Note finale = somme arithmétique EXACTE des notes individuelles
  • Test de cohérence final : si le même contenu dans un autre ordre
    aurait donné une autre note, votre notation est INCORRECTE → recommencez

R2. SOUPLESSE LOGIQUE
  • Si l'élève utilise une méthode/théorème/formulation différente du
    corrigé mais que sa logique est mathématiquement valide → totalité
    des points, methode_utilisee = "ALTERNATIVE VALIDE"
  • Évaluez la validité INTRINSÈQUE, pas la conformité de forme

R3. SANCTION DES RÉSULTATS MAGIQUES
  • Si un résultat est juste mais parachuté sans calcul/explication
    intermédiaire → 0 points, methode_utilisee = "ERRONÉE",
    justification = "Résultat parachuté sans démonstration"

R4. JUGER SUR LE CONTENU
  • Ne décidez JAMAIS du hors-sujet sur la base d'un en-tête (titre,
    nom d'élève, date). Seul le contenu mathématique/textuel compte.

R5. NIVEAU DE SESSION
  • Mode "MINISTERE" : rigueur ABSOLUE sur les étapes de justification
  • Modes "PROF_SOLO" / "ECOLE" : souplesse R2 plein appliquée

═══════════════════════════════════════════════════════════════
PRÉAMBULE — PROTOCOLE DE LECTURE DE LA COPIE (OBLIGATOIRE)
═══════════════════════════════════════════════════════════════

⚠️ AVANT TOUT : Comprenez bien comment lire la copie d'un élève.

1. ORDRE DES PAGES SANS IMPORTANCE — RÈGLE ABSOLUE
   Les pages de la copie vous sont présentées dans un ORDRE QUELCONQUE
   qui n'a AUCUNE valeur logique. La même copie scannée dans l'ordre
   inverse DOIT recevoir EXACTEMENT la même note. Pas un point de plus,
   pas un point de moins.
   • Page 1 visuelle ≠ première page logique de la copie
   • Un élève peut écrire la réponse à Q3 sur la première page scannée
   • Une réponse à la Question 1 peut se trouver sur la dernière page
   • La présence d'un en-tête "Page 1" ou "Page 2" est ignorée

2. PROTOCOLE D'INDEXATION OBLIGATOIRE (à effectuer mentalement AVANT
   toute notation)

   Étape A — Construire l'index de contenu page-par-page :
     Pour CHAQUE page fournie, identifiez TOUT son contenu en cherchant
     les marqueurs explicites (« 1) », « 2) », « Q1 », « a) », « b) »,
     « Exercice 1 », « ex 2 », etc.) écrits PAR L'ÉLÈVE dans la copie.
     Exemple d'index mental :
       Page 1 (visuelle) → contient début de Q3 et toute la Q2
       Page 2 (visuelle) → contient toute la Q1
       Page 3 (visuelle) → contient fin de Q3 et essai de Q4

   Étape B — Mapper chaque leafId du barème à un ou plusieurs blocs
   identifiés dans l'index. Si un leafId n'apparaît dans AUCUNE page de
   la copie, il sera noté 0 (NON_TRAITEE).

   Étape C — Pour chaque leafId, agréger les blocs identifiés (même
   s'ils sont éclatés sur plusieurs pages) AVANT de noter.

   Ce protocole rend la notation INDÉPENDANTE de l'ordre des pages.

3. JUGEZ SUR LE CONTENU, JAMAIS SUR L'EN-TÊTE
   Ne décidez JAMAIS qu'une copie est hors-sujet sur la seule base de
   son en-tête (titre, nom d'élève, "Devoir n°X", date, etc.).
   • L'en-tête peut mentionner "Devoir de chimie" alors que le contenu
     est bien des maths conformes au sujet → CONFORME
   • L'en-tête peut être vide ou faux → lire le contenu pour décider
   • Seul le contenu mathématique/textuel des réponses détermine si la
     copie traite le sujet ou non

4. LISEZ TOUTES LES PAGES AVANT DE STATUER
   Ne formez votre jugement (Gatekeeper inclus) qu'après avoir parcouru
   l'INTÉGRALITÉ des pages fournies. Une page apparemment hors-sujet
   peut être suivie d'autres pages parfaitement sur le sujet.

5. CONSTANCE — TEST DE COHÉRENCE
   Avant de finaliser votre JSON, posez-vous mentalement la question :
   "Si on me redonnait les mêmes pages dans un ordre différent, est-ce
   que je donnerais la même note ?" Si la réponse est NON, votre
   notation est INCORRECTE — recommencez en suivant strictement le
   protocole d'indexation ci-dessus.

═══════════════════════════════════════════════════════════════
ÉTAPE 1 — LE FILTRE DE SÉCURITÉ ("GATEKEEPER" HORS-SUJET)
═══════════════════════════════════════════════════════════════

Avant d'entamer la correction détaillée, effectuez une validation de
cohérence en DEUX NIVEAUX. La copie doit passer LES DEUX pour être
considérée CONFORME. Une seule faille → HORS_SUJET.

────────────────────────────────────────────────────────────────
NIVEAU 1.1 — Vérification de MATIÈRE
────────────────────────────────────────────────────────────────

  • Identifiez la matière du [SUJET OFFICIEL] (mathématiques, physique,
    chimie, français, anglais, histoire, philosophie, biologie, SVT, etc.)
  • Identifiez la matière de la [COPIE DE L'ÉLÈVE]
  • Si les deux matières ne correspondent pas → HORS_SUJET

  Exemples :
    • Sujet maths, copie chimie → HORS_SUJET
    • Sujet français, copie histoire → HORS_SUJET

────────────────────────────────────────────────────────────────
NIVEAU 1.2 — Vérification de CONCORDANCE DES ÉNONCÉS PRÉCIS
────────────────────────────────────────────────────────────────

⚠️ CRITIQUE — Ne pas se limiter à la matière. Vérifier que la copie traite
les MÊMES QUESTIONS / EXERCICES que ceux du sujet officiel.

Pour chaque question du barème officiel (voir structure JSON ci-dessous),
posez-vous la question :
  → "L'élève a-t-il tenté de répondre à CETTE question précise (ou à un
     sous-élément clairement identifiable de cette question) ?"

Règles strictes :

  A) MÊME MATIÈRE, AUTRE SUJET → HORS_SUJET
     • Sujet : "Résoudre l'équation différentielle y' + 2y = 0"
       Copie : "Calculer la dérivée de f(x) = x² + 3x"
       → HORS_SUJET (les deux sont des maths, mais la copie traite des
         dérivées simples au lieu d'équations différentielles)

     • Sujet : "Étude de la fonction f(x) = ln(x+2)"
       Copie : "Calcul de l'intégrale ∫ sin(x) dx"
       → HORS_SUJET (math contre math, mais sujets totalement différents)

     • Sujet : "Commentaire composé sur 'Le Rouge et le Noir'"
       Copie : "Dissertation sur Baudelaire"
       → HORS_SUJET (français contre français, mais œuvres différentes)

  B) MÊME SUJET, RÉPONSES PARTIELLES OU INCOMPLÈTES → CONFORME
     • L'élève n'a traité que 2 questions sur 5 → CONFORME, on note 0
       aux questions non traitées
     • L'élève a fait des erreurs partout → CONFORME, on note bas

  C) COPIE VIDE OU CONTENU ALÉATOIRE → HORS_SUJET
     • Page blanche, gribouillis, "je ne sais pas répondre" sans plus →
       HORS_SUJET

  D) COPIE QUI TRAITE DES NOTIONS PROCHES MAIS SANS LIEN DIRECT → HORS_SUJET
     • Sujet : "Étude de la suite (uₙ) définie par uₙ₊₁ = ½uₙ + 3"
       Copie : "Étude de la suite (vₙ) définie par vₙ = n² + 2n"
       → HORS_SUJET (la copie étudie UNE AUTRE suite, pas celle demandée)

CRITÈRE D'OR DU NIVEAU 1.2 :
   Pour être CONFORME, la copie doit montrer que l'élève a LU les énoncés
   du sujet officiel et traite ces énoncés-là spécifiquement. Si l'élève
   "fait des maths" mais sur d'autres exercices que ceux demandés, c'est
   HORS_SUJET (note 0 globale, pas de notation détaillée).

⚠️ TOLÉRANCE OBLIGATOIRE :
   • Une photo de tableau noir, manuscrite ou de qualité moyenne reste
     ACCEPTABLE tant que tu peux identifier au moins un lien avec le sujet.
   • Une photo floue mais qui contient visiblement des éléments du sujet
     (mots-clés, formules, numéros de question) → CONFORME, note ce que
     tu peux lire et marque les zones illisibles avec ZONE_INCOMPREHENSIBLE.
   • Ne rejette comme HORS_SUJET QUE si tu es CERTAIN que la copie traite
     un autre sujet. Dans le doute (ex: photo très floue impossible à lire),
     déclare CONFORME et utilise ZONE_INCOMPREHENSIBLE pour signaler les
     parties illisibles plutôt que de tout rejeter.

────────────────────────────────────────────────────────────────
RÈGLE DE SORTIE EN CAS DE HORS_SUJET
────────────────────────────────────────────────────────────────

Si NIVEAU 1.1 OU NIVEAU 1.2 échoue :
  • Fixez statut_conformite = "HORS_SUJET"
  • Fixez note_finale = "00 / <bareme_total>"
  • verification_initiale doit EXPLIQUER précisément l'écart :
      Exemple : "Le sujet officiel porte sur la résolution d'équations
       différentielles linéaires du premier ordre, mais la copie de l'élève
       traite du calcul de dérivées de polynômes — il s'agit d'un autre
       sujet de mathématiques. La copie ne répond à aucune des questions
       posées (Q1, Q2, Q3)."
  • Listez TOUTES les leafIds avec note_attribuee=0,
    methode_utilisee="NON_TRAITEE", analyse_prof="Copie hors-sujet :
    l'élève traite un autre exercice que celui demandé."
  • Sautez les étapes suivantes et générez directement le JSON final.

═══════════════════════════════════════════════════════════════
ÉTAPE 2 — ANALYSE PAR BLOCS, SOUPLESSE LOGIQUE, ZONES ILLISIBLES
═══════════════════════════════════════════════════════════════

⚠️ RÈGLE FONDAMENTALE — ANALYSE QUESTION-PAR-QUESTION :
   Vous DEVEZ traiter CHAQUE leafId du barème INDÉPENDAMMENT. Pour chaque
   question, vous devez :
     1. Localiser dans la copie la réponse qui correspond à CETTE question
        précise (chercher le numéro, le label, l'énoncé).
     2. Si vous ne trouvez PAS de réponse à cette question dans la copie :
        → note_attribuee = 0
        → methode_utilisee = "NON_TRAITEE"
        → analyse_prof = "Question non traitée dans la copie."
     3. Si vous trouvez une réponse : comparer au corrigé/cours et noter.

   ❌ INTERDIT : noter une question 100% sans avoir VU sa réponse spécifique
   dans la copie. Le fait que la copie ressemble globalement au corrigé NE
   suffit PAS — il faut vérifier chaque question séparément.

   ❌ INTERDIT : donner la note maximale globale parce que la copie ressemble
   au corrigé. Si la copie ne contient que la réponse aux questions 1 et 2,
   les questions 3, 4, 5 doivent avoir note=0, même si elles seraient dans
   le corrigé.

   ✓ EXEMPLE : Sujet = 3 questions (Q1:5pts, Q2:8pts, Q3:7pts).
     Copie = uniquement la réponse à Q1 (parfaite).
     → Note Q1 = 5/5, Note Q2 = 0/8, Note Q3 = 0/7. TOTAL = 5/20.
     PAS 20/20. PAS 6/20. Exactement 5/20.

Une fois cette règle bien comprise, appliquez les règles ci-dessous :

A. COUPLAGE AVEC LES CORRECTIONS MANUELLES (saisie prof)
   • Avant de noter une question, vérifiez si elle possède une entrée
     correspondante dans [CORRECTIONS MANUELLES DU PROF]. Si oui,
     substituez ou complétez la partie illisible par le texte explicite
     fourni par le professeur, et notez sur cette base réévaluée.

B. GESTION DES ZONES ILLISIBLES / INCOMPRÉHENSIBLES (OCR ou IA défaillants)
   • Si un mot, une expression ou une ligne entière est incompréhensible
     ou mal transcrite, NE BLOQUEZ PAS la correction globale.
   • Isolez la zone incertaine, attribuez 0 point pour cette sous-partie,
     et poursuivez normalement la correction de toutes les autres parties.
   • Marquez la sous-partie avec methode_utilisee = "ZONE_INCOMPREHENSIBLE"
     et le champ analyse_prof commence obligatoirement par
     "[ZONE_ILLISIBLE] : Veuillez saisir le sens de ce mot ou raisonnement
     sur votre écran pour mettre à jour la note de cette question."

C. SOUPLESSE ET RAISONNEMENT ALTERNATIF
   • Si l'élève utilise une méthode, un théorème ou une formulation
     différente du corrigé officiel mais que son cheminement logique est
     mathématiquement/scientifiquement valide et mène au bon résultat,
     accordez la TOTALITÉ des points.
   • Évaluez la validité intrinsèque de sa logique, pas la conformité
     stricte à une seule rédaction.
   • Marquez methode_utilisee = "ALTERNATIVE VALIDE" dans ce cas.

D. RIGUEUR PAR NIVEAU DE SESSION
   • En mode "MINISTERE" (BAC / Brevet / Concours), soyez d'une rigueur
     ABSOLUE sur les étapes de justification imposées par les consignes
     officielles : une étape sautée = perte de point même si le résultat
     final est correct.
   • En mode "PROF_SOLO" et "ECOLE", la souplesse de la règle C s'applique
     pleinement.

E. SANCTION DES "RÉSULTATS MAGIQUES"
   • Si un résultat est juste mais parachuté sans aucun calcul ni
     explication logique intermédiaire ("écriture magique"), attribuez
     0 point à la question pour rupture de logique.
   • Marquez methode_utilisee = "ERRONÉE" et expliquez la sanction dans
     analyse_prof.

F. CONSTANCE
   • Notes en pas de 0,5 (0 ; 0,5 ; 1 ; 1,5 ; …).
   • Jamais au-dessus du barème de la question.
   • Mêmes critères pour toutes les questions et toutes les copies.

═══════════════════════════════════════════════════════════════
ÉTAPE 3 — ARITHMÉTIQUE DE LA NOTE FINALE
═══════════════════════════════════════════════════════════════

  • Calculez la somme arithmétique stricte des notes attribuées à chaque
    bloc/question dans correction_detaillee.
  • La note_finale générée doit correspondre EXACTEMENT à cette somme,
    formatée "X / <bareme_total>" (ex: "13.5 / 20").
  • Les zones marquées "ZONE_INCOMPREHENSIBLE" restent à 0 tant que le
    professeur n'a pas saisi leur sens.

═══════════════════════════════════════════════════════════════
FORMAT DE SORTIE STRICT (JSON UNIQUEMENT, AUCUN MARKDOWN)
═══════════════════════════════════════════════════════════════

Retournez UNIQUEMENT l'objet JSON suivant (sans introduction, sans
conclusion, sans bloc \`\`\`) :

{
  "statut_conformite": "CONFORME" ou "HORS_SUJET",
  "verification_initiale": "Rapport succinct validant la concordance de la copie ou détaillant les raisons du rejet immédiat.",
  "note_finale": "X / <bareme_total>",
  "commentaire_general": "Synthèse pédagogique globale pour le professeur (forces, faiblesses, alertes sur les fraudes ou mentions de méthodes alternatives valides).",
  "audit_log_ia": "Résumé technique du niveau de confiance de la correction par l'IA pour l'archivage sécurisé.",
  "confidence": <nombre 0..1>,
  "correction_detaillee": [
    {
      "leafId": "<UUID EXACT fourni dans le barème — obligatoire>",
      "partie": "Nom de la section ou de l'exercice",
      "question": "Numéro/label de la question",
      "bareme_question": "<points max de la question, nombre>",
      "note_attribuee": "<points accordés, pas de 0,5, nombre>",
      "points_manquants": "<bareme_question - note_attribuee, nombre>",
      "reponse_detectee": "Résumé court (1-2 phrases) de ce que l'élève a écrit pour cette question. Si rien : 'Aucune réponse détectée.'",
      "methode_utilisee": "CONFORME AU CORRIGÉ" ou "ALTERNATIVE VALIDE" ou "ERRONÉE" ou "NON_TRAITEE" ou "ZONE_INCOMPREHENSIBLE",
      "justification": "Phrase courte justifiant la note attribuée (ce qui a été comptabilisé, ce qui manquait par rapport au corrigé/cours).",
      "analyse_prof": "Synthèse pédagogique 1-2 phrases destinée au professeur. Si ZONE_INCOMPREHENSIBLE, commencer par '[ZONE_ILLISIBLE] : ...'"
    }
  ]
}

En cas de HORS_SUJET, correction_detaillee doit lister TOUTES les leafIds
du barème, chacune avec :
  • note_attribuee = 0
  • points_manquants = bareme_question
  • reponse_detectee = "Aucune réponse détectée (copie hors-sujet)."
  • methode_utilisee = "NON_TRAITEE"
  • justification = "Copie hors-sujet : non évaluable."
  • analyse_prof = "Copie hors-sujet : l'élève traite un autre sujet."`;

// C3 (Sprint 3) — Mode fire-and-forget :
//   Le client peut passer async=true dans le body pour recevoir un 202
//   immédiat. La correction continue en background via EdgeRuntime.waitUntil()
//   même si le client ferme l'app ou perd la connexion. Le résultat final
//   est écrit en DB → le client le récupère via polling au retour foreground.
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

  // ═════════════════════════════════════════════════════════════════════════
  // C3 (Sprint 3 renforcé) — FIRE-AND-FORGET AVEC EdgeRuntime.waitUntil()
  // ═════════════════════════════════════════════════════════════════════════
  // On parse le body et l'auth AVANT toute chose (rapide). Puis on lance la
  // pipeline complète en tâche de fond via EdgeRuntime.waitUntil() — ça
  // garantit que Supabase ne kill pas l'isolate même si le client abandonne
  // la connexion (app fermée, réseau perdu). Le résultat est écrit en DB,
  // le client polling le récupère au retour foreground.
  // ═════════════════════════════════════════════════════════════════════════

  // 1. Parse body (rapide, hors try/catch principal)
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch (_) {
    return new Response(JSON.stringify({ error: "Body JSON invalide" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const copyId = (body.copyId as string) ?? "";
  if (!copyId) {
    return new Response(JSON.stringify({ error: "copyId requis" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // async=true par défaut → réponse immédiate + traitement en background
  const isAsync: boolean = body.async !== false;

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Non authentifié" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  // 1bis. AUTORISATION (audit 15/10/2026) — avant tout appel IA :
  //   a) l'appelant est un utilisateur connecté, propriétaire de l'examen ;
  //   b) les pages sont des images de NOTRE bucket « copies » (un PDF
  //      multi-pages compterait pour 1 crédit) et ≤ MAX_COPY_PAGES ;
  //   c) des crédits ont bien été réservés pour cette copie (ou relance
  //      Human-in-the-Loop incluse, plafonnée) → authorize_grading().
  //   Sans ce contrôle, l'Edge Function pouvait être appelée directement
  //   pour obtenir des corrections sans payer.
  {
    const jsonErr = (status: number, error: string, code?: string) =>
      new Response(JSON.stringify({ error, code }), {
        status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(SUPA_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userRes } = await userClient.auth.getUser();
    const callerId = userRes?.user?.id;
    if (!callerId) return jsonErr(401, "Session invalide.");

    const svc = createClient(SUPA_URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: copyRow } = await svc
      .from("student_copies")
      .select("id, page_images, locked_at, exams!inner(owner_id)")
      .eq("id", copyId)
      .maybeSingle();
    // deno-lint-ignore no-explicit-any
    const ownerId = (copyRow as any)?.exams?.owner_id;
    if (!copyRow || ownerId !== callerId) {
      return jsonErr(404, "Copie introuvable.");
    }
    const lockedAt = (copyRow as { locked_at?: string | null }).locked_at;
    if (lockedAt && new Date(lockedAt).getTime() < Date.now()) {
      return jsonErr(409, "Notes figées : copie publiée au casier depuis plus de 3 jours.", "COPY_LOCKED");
    }
    const pages = ((copyRow.page_images as string[] | null) ?? []);
    const MAX_COPY_PAGES = 60;
    if (pages.length > MAX_COPY_PAGES) {
      return jsonErr(400, `Copie trop longue (${pages.length} pages, max ${MAX_COPY_PAGES}).`, "TOO_MANY_PAGES");
    }
    const copiesPrefix = `${SUPA_URL.replace(/\/$/, "")}/storage/v1/object/public/copies/`;
    const badPage = pages.find((u) =>
      typeof u !== "string" ||
      !u.startsWith(copiesPrefix) ||
      !/\.(jpe?g|png|webp|gif)(\?|$)/i.test(u)
    );
    if (badPage !== undefined) {
      return jsonErr(
        400,
        "Pages invalides : seules les photos (JPG, PNG, WEBP) envoyées par l'application sont acceptées.",
        "INVALID_PAGES",
      );
    }

    const isHitl = Array.isArray(body.manualCorrections) &&
      (body.manualCorrections as unknown[]).length > 0;
    const { data: authRows, error: authErr } = await svc.rpc("authorize_grading", {
      p_copy_id: copyId,
      p_hitl: isHitl,
    });
    // deno-lint-ignore no-explicit-any
    const authRow = Array.isArray(authRows) ? (authRows[0] as any) : null;
    if (authErr || !authRow?.out_ok) {
      const reason = authRow?.out_reason ?? "PAYMENT_REQUIRED";
      const msg = reason === "HITL_LIMIT_REACHED"
        ? "Nombre maximal de relances gratuites atteint pour cette copie (3)."
        : "Aucun crédit réservé pour cette copie. Lancez la correction depuis l'application.";
      return jsonErr(402, msg, reason);
    }
  }

  // 2. Pipeline complète encapsulée en fonction async
  const runPipeline = async (): Promise<Response> => {
    // Récupère les autres paramètres depuis body (accessible via closure)
    const sessionLevel: string =
      (body.sessionLevel as string) ?? "PROF_SOLO";
    const manualCorrections: unknown[] =
      (body.manualCorrections as unknown[]) ?? [];

    try {

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

    // 2. Charge l'examen + questions + sub-questions
    const { data: exam, error: examErr } = await supabase
      .from("exams")
      .select("*, questions(*, sub_questions(*))")
      .eq("id", copy.exam_id)
      .single();
    if (examErr) throw new Error(`Examen introuvable : ${examErr.message}`);

    if (!copy.page_images || copy.page_images.length === 0) {
      throw new Error("Aucune page à corriger.");
    }

    // Bucket « copies » privé (audit 15/10/2026) : les URL stockées ont le
    // format public ; on les remplace par des liens signés de 15 min, le
    // temps que Claude télécharge les pages.
    {
      const signer = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      const marker = "/storage/v1/object/public/copies/";
      copy.page_images = await Promise.all(
        (copy.page_images as string[]).map(async (u) => {
          const i = u.indexOf(marker);
          if (i < 0) return u;
          const objectPath = decodeURIComponent(u.slice(i + marker.length).split("?")[0]);
          const { data, error } = await signer.storage
            .from("copies")
            .createSignedUrl(objectPath, 900);
          if (error || !data?.signedUrl) {
            throw new Error("Impossible de lire une page de la copie (lien signé).");
          }
          return data.signedUrl;
        }),
      );
    }

    // ─────────────────────────────────────────────────────────────────────
    // FILET DE SÉCURITÉ : rejet immédiat si les URLs ne sont pas publiques
    // OU si les fichiers sont dans des formats non supportés par Claude.
    // ─────────────────────────────────────────────────────────────────────
    const isPublicUrl = (s: unknown): boolean =>
      typeof s === "string" &&
      (s.startsWith("http://") || s.startsWith("https://"));

    // Formats supportés par Claude vision (images : jpg, jpeg, png, gif, webp)
    // Formats supportés par Claude document (pdf)
    // Tout le reste (heic, docx, doc, etc.) doit être rejeté en amont.
    const getExt = (url: string): string => {
      const m = url.toLowerCase().match(/\.([a-z0-9]+)(?:\?|$)/);
      return m ? m[1] : "";
    };
    const SUPPORTED_IMAGE_EXTS = ["jpg", "jpeg", "png", "gif", "webp"];
    const SUPPORTED_DOC_EXTS = ["pdf"];
    const SUPPORTED_EXTS = [...SUPPORTED_IMAGE_EXTS, ...SUPPORTED_DOC_EXTS];

    // Construit dynamiquement le bon type de content selon l'extension
    // deno-lint-ignore no-explicit-any
    const buildFileContent = (url: string): any => {
      const ext = getExt(url);
      if (SUPPORTED_IMAGE_EXTS.includes(ext) || ext === "") {
        // ext vide = on tente comme image (cas d'URL signée sans extension)
        return { type: "image", source: { type: "url", url } };
      }
      if (SUPPORTED_DOC_EXTS.includes(ext)) {
        return { type: "document", source: { type: "url", url } };
      }
      // Sinon → format non supporté → throw plus haut
      throw new Error(
        `Format de fichier non supporté : .${ext}. ` +
          `Utilisez JPG, PNG, WEBP ou PDF uniquement. ` +
          `Les fichiers HEIC (iPhone) et DOCX ne sont pas pris en charge — ` +
          `convertissez-les en JPG ou PDF avant import.`,
      );
    };

    const badCopyPaths = (copy.page_images as string[]).filter(
      (p) => !isPublicUrl(p),
    );
    if (badCopyPaths.length > 0) {
      throw new Error(
        "Les pages de la copie ne sont pas correctement uploadées " +
          "(chemins locaux détectés). Veuillez re-scanner la copie depuis " +
          "l'application v1.0.5 ou plus récente.",
      );
    }

    const subjectImages: string[] =
      (exam.subject_images as string[] | undefined) ?? [];
    const badSubjectPaths = subjectImages.filter((p) => !isPublicUrl(p));
    if (badSubjectPaths.length > 0 && subjectImages.length > 0) {
      throw new Error(
        "Les images du sujet ne sont pas accessibles (chemins locaux). " +
          "Le sujet a été créé avec une ancienne version. Veuillez recréer " +
          "l'examen depuis l'application v1.0.5 (étape 'Importer le sujet').",
      );
    }

    const cs = exam.correction_source ?? {};
    const allCorrectionPaths: string[] = [
      ...((cs.documentPaths as string[] | undefined) ?? []),
      ...((cs.answerKeyPaths as string[] | undefined) ?? []),
      ...((cs.coursePaths as string[] | undefined) ?? []),
    ];
    const badCorrectionPaths = allCorrectionPaths.filter((p) => !isPublicUrl(p));
    if (badCorrectionPaths.length > 0) {
      throw new Error(
        "Les documents du corrigé/cours ne sont pas accessibles " +
          "(chemins locaux). Veuillez ré-importer la source de correction " +
          "depuis l'application v1.0.5 (étape 'Source de correction').",
      );
    }

    // Vérif format : on liste les extensions non supportées dès maintenant
    const allUrls = [
      ...(copy.page_images as string[]),
      ...subjectImages,
      ...allCorrectionPaths,
    ];
    const badFormats = allUrls
      .map((u) => ({ url: u, ext: getExt(u) }))
      .filter((x) => x.ext !== "" && !SUPPORTED_EXTS.includes(x.ext));
    if (badFormats.length > 0) {
      const exts = [...new Set(badFormats.map((b) => b.ext))].join(", ");
      throw new Error(
        `Format(s) de fichier non supporté(s) détecté(s) : ${exts}. ` +
          `Claude vision accepte uniquement JPG, PNG, WEBP, GIF, PDF. ` +
          `Les fichiers HEIC (iPhone) et DOCX doivent être convertis en JPG ` +
          `ou PDF avant import.`,
      );
    }

    // Au moins UNE référence visuelle doit être fournie, sinon Claude ne peut
    // pas faire de comparaison fiable et noterait au pif.
    const hasAnyReference = subjectImages.length > 0 ||
      allCorrectionPaths.length > 0 ||
      ((cs.generatedContent as string | undefined) ?? "").trim().length > 0;
    if (!hasAnyReference) {
      throw new Error(
        "Aucune référence visuelle disponible (ni sujet, ni corrigé, ni cours). " +
          "Importez au moins une photo du sujet OU un corrigé type pour permettre " +
          "à l'IA de comparer.",
      );
    }

    // 3. Barème : structure pour le prompt + liste plate des leafIds
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
        ? {
          partie: q.label,
          statement: q.statement,
          subQuestions: subs,
        }
        : {
          partie: q.label,
          statement: q.statement,
          leafId: q.id,
          maxPoints: Number(q.points) || 0,
        };
    });

    const allLeafIds: string[] = [];
    // deno-lint-ignore no-explicit-any
    (exam.questions ?? []).forEach((q: any) => {
      // deno-lint-ignore no-explicit-any
      const subs = (q.sub_questions ?? []) as any[];
      if (subs.length > 0) {
        for (const s of subs) allLeafIds.push(s.id);
      } else {
        allLeafIds.push(q.id);
      }
    });

    // Barème total
    const baremeTotal = Number(exam.total_points) ||
      (exam.questions ?? []).reduce((acc: number, q: any) => {
        const subs = q.sub_questions ?? [];
        if (subs.length > 0) {
          return acc + subs.reduce(
            (a: number, s: any) => a + (Number(s.points) || 0),
            0,
          );
        }
        return acc + (Number(q.points) || 0);
      }, 0);

    // 4. Source de correction officielle (v3+ format : answerKeyPaths + coursePaths)
    const correctionSource = exam.correction_source ?? {};
    const correctionType: string = correctionSource.type ?? "";
    const answerKeyPathsNew: string[] =
      (correctionSource.answerKeyPaths as string[] | undefined) ?? [];
    const coursePathsNew: string[] =
      (correctionSource.coursePaths as string[] | undefined) ?? [];
    const legacyDocs: string[] =
      (correctionSource.documentPaths as string[] | undefined) ?? [];
    const generatedContent: string = correctionSource.generatedContent ?? "";

    const finalAnswerKeyPaths = answerKeyPathsNew.length > 0
      ? answerKeyPathsNew
      : (correctionType === "answerKey" ? legacyDocs : []);
    const finalCoursePaths = coursePathsNew.length > 0
      ? coursePathsNew
      : (correctionType === "course" ? legacyDocs : []);
    const finalGeneratedText = correctionType === "aiGenerated" ||
        generatedContent
      ? generatedContent
      : "";

    // 5. Construit le contenu multi-images
    // deno-lint-ignore no-explicit-any
    const content: any[] = [];

    // === Niveau de session ===
    content.push({
      type: "text",
      text:
        `═══════════════════════════════════════════════════════════
[NIVEAU DE SESSION] : ${sessionLevel}
═══════════════════════════════════════════════════════════
${
          sessionLevel === "MINISTERE"
            ? "Mode rigueur ABSOLUE sur les étapes de justification."
            : "Mode standard avec souplesse logique (méthodes alternatives valides acceptées)."
        }`,
    });

    // === Barème total ===
    content.push({
      type: "text",
      text:
        `═══════════════════════════════════════════════════════════
[BARÈME TOTAL] : ${baremeTotal} points
═══════════════════════════════════════════════════════════`,
    });

    // === Sujet officiel ===
    content.push({
      type: "text",
      text:
        `═══════════════════════════════════════════════════════════
[SUJET OFFICIEL DE L'EXAMEN]
═══════════════════════════════════════════════════════════

Examen : "${exam.title}"
${exam.class_name ? `Classe : ${exam.class_name}` : ""}

Structure et barème officiel :

${JSON.stringify(questionsForPrompt, null, 2)}

LeafIds attendus (TOUTES doivent figurer dans correction_detaillee) :
${JSON.stringify(allLeafIds)}`,
    });

    if (exam.subject_images && exam.subject_images.length > 0) {
      content.push({
        type: "text",
        text:
          `Voici les ${exam.subject_images.length} page(s) ORIGINALE(S) du sujet :`,
      });
      for (const url of exam.subject_images) {
        content.push(buildFileContent(url));
      }
    }

    // === Source de correction officielle ===
    if (finalAnswerKeyPaths.length > 0) {
      content.push({
        type: "text",
        text:
          `═══════════════════════════════════════════════════════════
[SOURCE DE CORRECTION OFFICIELLE — CORRIGÉ TYPE]
═══════════════════════════════════════════════════════════

Voici les ${finalAnswerKeyPaths.length} page(s) du corrigé type officiel.
Comparez strictement à ce corrigé, en appliquant la règle de souplesse
(une méthode alternative correcte mérite la totalité des points).`,
      });
      for (const url of finalAnswerKeyPaths) {
        content.push(buildFileContent(url));
      }
    }
    if (finalCoursePaths.length > 0) {
      content.push({
        type: "text",
        text:
          `═══════════════════════════════════════════════════════════
[SOURCE DE CORRECTION OFFICIELLE — COURS / SUPPORT]
═══════════════════════════════════════════════════════════

Voici les ${finalCoursePaths.length} page(s) du cours fourni par le
professeur. Évaluez la copie selon ces notions, sans inventer de contenu
absent du cours.`,
      });
      for (const url of finalCoursePaths) {
        content.push(buildFileContent(url));
      }
    }
    if (finalGeneratedText.trim().length > 0) {
      content.push({
        type: "text",
        text:
          `═══════════════════════════════════════════════════════════
[SOURCE DE CORRECTION OFFICIELLE — CORRIGÉ IA VALIDÉ PAR LE PROF]
═══════════════════════════════════════════════════════════

${finalGeneratedText}`,
      });
    }
    if (
      finalAnswerKeyPaths.length === 0 &&
      finalCoursePaths.length === 0 &&
      finalGeneratedText.trim().length === 0
    ) {
      content.push({
        type: "text",
        text:
          `═══════════════════════════════════════════════════════════
[AUCUNE SOURCE DE CORRECTION FOURNIE]
═══════════════════════════════════════════════════════════
Utilisez vos connaissances générales avec prudence. Confidence basse en
cas de doute. Le filtre Gatekeeper s'applique malgré tout.`,
      });
    }

    // === Corrections manuelles du prof (optionnel) ===
    if (Array.isArray(manualCorrections) && manualCorrections.length > 0) {
      content.push({
        type: "text",
        text:
          `═══════════════════════════════════════════════════════════
[CORRECTIONS MANUELLES DU PROF — Zones préalablement clarifiées]
═══════════════════════════════════════════════════════════

${JSON.stringify(manualCorrections, null, 2)}

Substituez ces textes aux zones illisibles correspondantes avant notation.`,
      });
    }

    // ─────────────────────────────────────────────────────────────────────
    // BREAKPOINT DE CACHE — tout ce qui précède (sujet + corrigé + cours +
    // barème + corrections manuelles) est FIXE par examen → mis en cache
    // pour être réutilisé sur toutes les copies du même examen. La copie
    // de l'élève vient APRÈS ce marqueur → jamais cachée (unique par copie).
    // Économie : ~5-10k tokens à 10% du prix dès la 2e copie du batch.
    // ─────────────────────────────────────────────────────────────────────
    if (content.length > 0) {
      const lastBlock = content[content.length - 1];
      lastBlock.cache_control = { type: "ephemeral", ttl: "1h" };
    }

    // === Copie de l'élève (transcription multimodale = pages images) ===
    content.push({
      type: "text",
      text:
        `═══════════════════════════════════════════════════════════
[COPIE DE L'ÉLÈVE À ÉVALUER]
═══════════════════════════════════════════════════════════

Nom : ${copy.student_name}
${copy.student_ref ? `Référence : ${copy.student_ref}` : ""}

Voici les ${copy.page_images.length} page(s) de la copie.

⚠️ RAPPEL :
  • Les pages peuvent être dans n'importe quel ORDRE — ce n'est pas
    nécessairement l'ordre logique de la copie.
  • LISEZ TOUTES les pages d'abord, puis associez chaque réponse au
    bon leafId en vous basant sur les labels/numéros visibles dans la
    copie (1), 2), Q1, Exercice 1, etc.).
  • Une réponse à la Question 1 peut se trouver sur n'importe quelle page.
  • L'en-tête (nom, titre, date) ne détermine PAS le statut hors-sujet.
    Seul le CONTENU des réponses compte.

Lisez attentivement l'écriture manuscrite et appliquez le protocole.`,
    });
    for (const url of copy.page_images) {
      content.push(buildFileContent(url));
    }

    // === Instruction finale ===
    content.push({
      type: "text",
      text:
        `═══════════════════════════════════════════════════════════
INSTRUCTION FINALE — Appliquez maintenant le protocole en 3 étapes :
═══════════════════════════════════════════════════════════

1. ÉTAPE 1 — GATEKEEPER (DEUX NIVEAUX OBLIGATOIRES)

   1.1 — La matière de la copie correspond-elle à celle du sujet ?
         • Sujet maths → copie maths ? Sujet français → copie français ?
         • Si NON → HORS_SUJET, stoppez ici.

   1.2 — La copie traite-t-elle les MÊMES exercices/questions que le
         barème officiel ci-dessus ?
         • Examinez chaque leafId du barème (énoncés visibles ci-dessus)
         • La copie doit montrer une tentative de réponse à AU MOINS UNE
           question identifiable du barème.
         • Si l'élève traite des exercices DIFFÉRENTS dans la même matière
           (ex: dérivées au lieu d'équations différentielles) → HORS_SUJET
         • Si l'élève "fait des maths" mais sur d'autres énoncés que ceux
           demandés → HORS_SUJET

   En cas de HORS_SUJET (échec NIVEAU 1.1 OU NIVEAU 1.2) :
     → statut_conformite="HORS_SUJET"
     → note_finale="00 / ${baremeTotal}"
     → verification_initiale = explication précise de l'écart
     → correction_detaillee = TOUTES les leafIds (${
          JSON.stringify(allLeafIds)
        })
       avec note_attribuee=0, methode_utilisee="NON_TRAITEE",
       analyse_prof="Copie hors-sujet : l'élève traite un autre exercice
        que celui demandé."
     → STOPPEZ ici, ne passez pas à l'étape 2.

2. ÉTAPE 2 — ANALYSE PAR BLOCS (uniquement si Gatekeeper passé)

   Pour CHAQUE leafId du barème, identifiez la réponse correspondante
   dans la copie, comparez au corrigé/cours, notez selon les règles A-F.
   Marquez methode_utilisee correctement.

3. ÉTAPE 3 — ARITHMÉTIQUE

   note_finale = somme exacte des note_attribuee, formatée
   "X / ${baremeTotal}".

═══════════════════════════════════════════════════════════
RAPPEL FINAL — Le NIVEAU 1.2 du Gatekeeper est SOUVENT IGNORÉ.
Vérifiez VRAIMENT que les énoncés de la copie correspondent à ceux du
sujet officiel. Si l'élève fait un autre exercice de la même matière,
c'est HORS_SUJET. Ne soyez pas indulgent sur ce point.
═══════════════════════════════════════════════════════════

Retournez UNIQUEMENT le JSON, sans markdown, sans préambule.`,
    });

    // 6. Appel Claude — max_tokens adaptatif selon le nombre de questions
    //    (chaque entrée correction_detaillee fait ~150-300 tokens, on prévoit large)
    const adaptiveMaxTokens = Math.min(
      8192,
      4096 + allLeafIds.length * 300,
    );
    const claudeRaw = await callClaude(SYSTEM_PROMPT, content, adaptiveMaxTokens);
    const parsed = extractJson(claudeRaw);

    if (
      !parsed?.correction_detaillee ||
      !Array.isArray(parsed.correction_detaillee)
    ) {
      throw new Error("Format JSON invalide : correction_detaillee manquant.");
    }

    const isOffTopic = parsed.statut_conformite === "HORS_SUJET";
    const verificationInitiale =
      typeof parsed.verification_initiale === "string"
        ? parsed.verification_initiale
        : "";
    const commentaireGeneral =
      typeof parsed.commentaire_general === "string"
        ? parsed.commentaire_general
        : "";
    const auditLog = typeof parsed.audit_log_ia === "string"
      ? parsed.audit_log_ia
      : "";

    // Confidence : prend le champ explicite si présent, sinon 1.0 si hors-sujet, sinon 0.75
    let confidence = typeof parsed.confidence === "number"
      ? parsed.confidence
      : (isOffTopic ? 1.0 : 0.75);
    confidence = Math.max(0, Math.min(1, confidence));

    // 7. Construit le general_comment Final avec marqueur magique pour hors-sujet
    const generalCommentFinal = isOffTopic
      ? `${OFF_TOPIC_MARKER}${
        verificationInitiale || commentaireGeneral ||
        "Copie hors-sujet : non évaluable."
      }`
      : commentaireGeneral;

    // 8. Met à jour la copie
    await supabase
      .from("student_copies")
      .update({
        status: "graded",
        general_comment: generalCommentFinal,
        confidence,
        graded_at: new Date().toISOString(),
      })
      .eq("id", copyId);

    // 9. Convertit correction_detaillee → question_grades
    await supabase.from("question_grades").delete().eq("copy_id", copyId);

    // deno-lint-ignore no-explicit-any
    const grades: any[] = [];
    for (const item of parsed.correction_detaillee) {
      const leafId = item.leafId;
      if (!leafId || typeof leafId !== "string") continue;
      const score = isOffTopic ? 0 : (Number(item.note_attribuee) || 0);
      const methode = String(item.methode_utilisee ?? "").trim();
      const reponseDetectee = String(item.reponse_detectee ?? "").trim();
      const justification = String(item.justification ?? "").trim();
      const analyseProf = String(item.analyse_prof ?? "").trim();
      const baremeQ = Number(item.bareme_question) || 0;
      const pointsManquants = Number(item.points_manquants) ||
          Math.max(0, baremeQ - score);

      // Compose le commentaire structuré façon "rapport correcteur expert"
      const lines: string[] = [];
      if (reponseDetectee) {
        lines.push(`📝 Réponse détectée : ${reponseDetectee}`);
      }
      if (justification) {
        lines.push(`💡 Justification : ${justification}`);
      }
      if (pointsManquants > 0 && !isOffTopic && methode !== "NON_TRAITEE") {
        lines.push(`➖ Points manquants : ${pointsManquants}`);
      }
      if (analyseProf) {
        lines.push(`👨‍🏫 ${analyseProf}`);
      }
      let comment = lines.length > 0
        ? lines.join("\n")
        : (analyseProf || "Aucune analyse disponible.");

      // Préfixe magique pour zones illisibles (détection côté Flutter)
      if (methode === "ZONE_INCOMPREHENSIBLE" &&
          !comment.startsWith(ZONE_ILLISIBLE_MARKER) &&
          !comment.includes("[ZONE_ILLISIBLE]")) {
        comment = `${ZONE_ILLISIBLE_MARKER}${comment}`;
      }

      grades.push({
        copy_id: copyId,
        leaf_id: leafId,
        score,
        comment,
      });
    }
    if (grades.length > 0) {
      await supabase.from("question_grades").insert(grades);
    }

    // Grille v5 : la correction a abouti → le débit de crédits de cette copie
    // devient définitif (les crédits avaient été réservés au lancement, en
    // fonction du nombre de pages). Fait côté serveur car en mode async le
    // client ne connaît pas l'issue réelle de la correction.
    try {
      const adminFinal = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      await adminFinal.rpc("finalize_copy_charge", { p_copy_id: copyId });
    } catch (finErr) {
      console.error("[grade-copy] finalize_copy_charge failed:", finErr);
    }

    // 10. Réponse — on renvoie aussi le format brut Michel + nos champs internes
    const responsePayload = {
      // Format Michel (utile pour debug / futurs modules)
      statut_conformite: parsed.statut_conformite,
      verification_initiale: verificationInitiale,
      note_finale: parsed.note_finale,
      commentaire_general: commentaireGeneral,
      audit_log_ia: auditLog,
      correction_detaillee: parsed.correction_detaillee,
      // Champs internes (compatibilité ascendante avec le client Flutter)
      is_off_topic: isOffTopic,
      rejection_reason: isOffTopic
        ? (verificationInitiale || commentaireGeneral)
        : "",
      generalComment: commentaireGeneral,
      confidence,
      grades: grades.map((g) => ({
        leafId: g.leaf_id,
        score: g.score,
        comment: g.comment,
      })),
    };

    return new Response(JSON.stringify(responsePayload), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error("[grade-copy] pipeline error:", message);

      // C3 : en mode async, le client a déjà reçu 202 — il ne verra pas ce
      // 500. On écrit donc l'erreur DIRECTEMENT en DB pour que le polling
      // client la remonte. Utilise service_role pour bypass RLS.
      try {
        const admin = createClient(
          Deno.env.get("SUPABASE_URL")!,
          Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
        );
        await admin
          .from("student_copies")
          .update({
            status: "error",
            general_comment: `❌ Échec correction : ${message}`,
            confidence: 0,
          })
          .eq("id", copyId);
        // Échec technique → les crédits réservés pour cette copie sont
        // remis en solde immédiatement (idempotent, multi-lots).
        await admin.rpc("refund_credits", {
          p_copy_id: copyId,
          p_reason: "grade_copy_error",
        });
      } catch (dbErr) {
        console.error(
          "[grade-copy] failed to write error to DB:",
          dbErr,
        );
      }

      return new Response(JSON.stringify({ error: message }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  };

  // 3. Lance la pipeline
  if (isAsync) {
    // ═══════════════════════════════════════════════════════════════════
    // MODE ASYNC : fire-and-forget avec EdgeRuntime.waitUntil()
    // ═══════════════════════════════════════════════════════════════════
    // La pipeline continue en tâche de fond même si le client cancel la
    // requête HTTP (app en background, réseau perdu). Supabase garantit
    // que l'isolate reste vivant jusqu'à la fin du promise passé à
    // waitUntil (dans la limite du timeout Edge Function, ~150s).
    const bgTask = runPipeline().catch((err) => {
      console.error("[grade-copy] uncaught bg task:", err);
    });
    // @ts-ignore — EdgeRuntime injecté par Supabase Edge Runtime
    if (typeof EdgeRuntime !== "undefined" && EdgeRuntime.waitUntil) {
      // @ts-ignore
      EdgeRuntime.waitUntil(bgTask);
    }

    console.log(
      `[grade-copy] async accepted for copy=${copyId} — pipeline in bg`,
    );
    return new Response(
      JSON.stringify({
        status: "processing",
        message:
          "Correction en cours. Le résultat sera écrit en base et récupéré via polling.",
      }),
      {
        status: 202,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  // MODE SYNC (legacy) : attend le résultat et le renvoie au client
  return await runPipeline();
});