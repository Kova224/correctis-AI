# Obtenir les clés API (Claude Anthropic + Google Cloud Vision)

Tu auras besoin de **2 clés** pour la correction IA réelle. Les deux ont des **quotas gratuits** suffisants pour le développement.

---

## 1. Anthropic Claude API (correction IA) — 5 minutes

### Étapes

1. Va sur **https://console.anthropic.com/**
2. Inscris-toi (email + mot de passe, ou Google)
3. Une fois connecté, va dans **Settings → API Keys** (menu de gauche)
4. Clique **+ Create Key**
   - Name : `Correctis`
   - Workspace : Default Workspace
   - **Create Key**
5. **Copie immédiatement la clé** (commence par `sk-ant-api03-...`). Tu ne pourras plus la voir après — note-la dans un endroit sûr.

### Crédits gratuits

Anthropic offre **5 $ de crédits gratuits** à la création du compte. Avec Claude Haiku (~0,25 € / million tokens entrée), ça représente **plusieurs milliers de copies corrigées gratuitement** pour du test.

Pour ajouter du crédit ensuite : **Settings → Billing → Add credits** (minimum 5 $).

---

## 2. Google Cloud Vision API (OCR) — 10 minutes

### Étapes

1. Va sur **https://console.cloud.google.com/**
2. Connecte-toi avec ton compte Google
3. Si premier usage : accepte les conditions, sélectionne le pays Sénégal (ou ton pays)
4. Crée un projet :
   - En haut, clique le sélecteur de projet → **Nouveau projet**
   - Nom : `Correctis`
   - **Créer**
5. Active l'API Vision :
   - Menu de gauche → **APIs et services → Bibliothèque** (ou cherche "Vision")
   - Cherche **Cloud Vision API** → clique dessus → **Activer**
6. Active la facturation (obligatoire même pour le quota gratuit) :
   - Menu → **Facturation** → suis l'assistant
   - Tu peux mettre une carte bancaire — **les premiers 1 000 appels par mois sont GRATUITS**, et Google ne te débite que si tu dépasses (et avec ton autorisation explicite)
7. Génère une clé API :
   - Menu → **APIs et services → Identifiants**
   - **+ Créer des identifiants → Clé API**
   - Une popup apparaît avec ta clé (commence par `AIza...`). **Copie-la.**
   - Clique **Restreindre la clé** :
     - **Restrictions liées aux API** → **Restreindre la clé** → coche **Cloud Vision API** uniquement
     - **Enregistrer**

### Quota gratuit

**1 000 unités/mois gratuites** (= ~1000 pages OCR), puis **1,50 $ / 1000 unités** au-delà. Pour un prof qui scanne 200 copies/mois, c'est largement dans le quota gratuit.

---

## 3. Mettre les clés dans Supabase Edge Functions

Une fois les **2 clés copiées**, va sur Supabase :

1. Dashboard → **Edge Functions → Secrets** (https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/settings/functions)
2. Ajoute **2 secrets** :
   - **Name** : `ANTHROPIC_API_KEY` | **Value** : `sk-ant-api03-...` (ta clé Anthropic)
   - **Name** : `GOOGLE_VISION_API_KEY` | **Value** : `AIza...` (ta clé Google)
3. **Save**

Ces secrets seront accessibles **uniquement** depuis les Edge Functions côté serveur. **Jamais embarqués dans l'app mobile.** C'est ce qui rend l'architecture sécurisée.

---

## Récap

| Service | URL | Clé attendue | Quota gratuit |
|---|---|---|---|
| Anthropic Claude | console.anthropic.com | `sk-ant-api03-...` | 5 $ de crédit |
| Google Cloud Vision | console.cloud.google.com | `AIza...` | 1000 req/mois |

Quand tu as les 2 clés ajoutées dans Supabase, dis-moi — je déploierai les Edge Functions et brancherai l'app.
