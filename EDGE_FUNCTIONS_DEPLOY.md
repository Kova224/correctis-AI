# Déployer les Edge Functions Correctis

Deux fonctions à déployer sur Supabase :
- **extract-questions** — OCR + structuration du sujet
- **grade-copy** — OCR + correction d'une copie

## Prérequis : les 2 secrets API

Avant tout, vérifie que les clés sont bien dans Supabase
(Dashboard → Project Settings → Edge Functions → Secrets, ou
https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/settings/functions) :

- `ANTHROPIC_API_KEY` = `sk-ant-api03-...`
- `GOOGLE_VISION_API_KEY` = `AIza...`

(`SUPABASE_URL` et `SUPABASE_ANON_KEY` sont injectés automatiquement par Supabase, rien à faire.)

---

## Méthode 1 — Supabase CLI (recommandée)

### a) Installer la CLI

Sous Windows (PowerShell) :

```powershell
# Via Scoop
scoop install supabase

# OU via npm
npm install -g supabase
```

Vérifie : `supabase --version`

### b) Se connecter et lier le projet

```powershell
supabase login
# (ouvre le navigateur pour autoriser)

cd "C:\Users\Bienvenu\Documents\Corrector AI\Correctis AI\correctis_app"
supabase link --project-ref nqwymypfykiengbqdqim
```

### c) Déployer les 2 fonctions

```powershell
supabase functions deploy extract-questions
supabase functions deploy grade-copy
```

Tu verras une URL de déploiement pour chaque fonction. C'est bon.

---

## Méthode 2 — Dashboard (sans CLI)

Si tu ne veux pas installer la CLI :

1. Va sur https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/functions
2. Clique **Create a new function**
3. Nom : `extract-questions`
4. Colle le contenu de `supabase/functions/extract-questions/index.ts`
   - ⚠️ Remplace les imports `../_shared/cors.ts` et `../_shared/providers.ts`
     par le contenu inline (le dashboard ne gère pas les fichiers partagés).
   - Plus simple : utilise la CLI (méthode 1).
5. **Deploy**
6. Répète pour `grade-copy`

> La méthode CLI est vraiment plus simple à cause des fichiers `_shared/`.
> Je recommande d'installer la CLI.

---

## Vérifier que ça marche

Une fois déployées, les fonctions sont disponibles à :
- `https://nqwymypfykiengbqdqim.supabase.co/functions/v1/extract-questions`
- `https://nqwymypfykiengbqdqim.supabase.co/functions/v1/grade-copy`

Dans l'app Correctis :
1. Crée un examen → importe une vraie photo de sujet → "Analyser"
   → si l'OCR réelle marche, tu verras les **vraies questions** de ta photo
   → sinon, l'app retombe automatiquement sur le mock (pas de blocage)
2. Scanne une copie → "Terminer cette copie"
   → la correction réelle se lance via `grade-copy`

Les logs des fonctions sont visibles dans :
https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/functions
→ clique sur une fonction → onglet **Logs**

---

## Comportement de l'app

L'app est conçue pour être **résiliente** :
- Si les Edge Functions sont déployées + clés OK → **vraie OCR + vraie correction IA**
- Si une fonction échoue (clé manquante, quota dépassé, réseau) → **fallback mock automatique**

Donc tu peux continuer à développer/tester même sans les fonctions déployées.

---

## Coûts à surveiller

- **Google Vision** : 1000 pages/mois gratuites, puis ~1,50 $/1000
- **Claude Haiku** : ~0,25 $/million tokens — une correction de copie ≈ 2000-4000 tokens
  → environ 0,001 $ par copie, soit **~1 $ pour 1000 copies corrigées**
- **Edge Functions Supabase** : 500 000 invocations/mois gratuites

Pour un usage scolaire normal, tu restes dans les quotas gratuits ou presque.
