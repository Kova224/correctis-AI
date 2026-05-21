# Setup OAuth — Google, Facebook, LinkedIn

Pour chaque provider, le principe est identique :
1. Créer une application OAuth chez le provider
2. Renseigner le **Callback URL** Supabase
3. Récupérer **Client ID** + **Client Secret**
4. Les coller dans Supabase Dashboard → Authentication → Providers

**Callback URL Supabase pour tous les providers** :

```
https://nqwymypfykiengbqdqim.supabase.co/auth/v1/callback
```

---

## 1. Google OAuth (le plus simple, ~10 min)

### a) Côté Google Cloud Console

1. Va sur https://console.cloud.google.com/projectcreate
2. Crée un projet nommé `Correctis`
3. Active l'API **Google+ API** ou **People API** (Library → cherche, Enable)
4. Va dans **APIs & Services → OAuth consent screen** :
   - User Type : **External**
   - App name : `Correctis`
   - User support email : ton email
   - Developer contact : ton email
   - Save → Save → Save → Back to Dashboard
5. Va dans **APIs & Services → Credentials** :
   - **+ Create Credentials → OAuth client ID**
   - Application type : **Web application**
   - Name : `Correctis Supabase`
   - **Authorized redirect URIs** : ajoute exactement :
     ```
     https://nqwymypfykiengbqdqim.supabase.co/auth/v1/callback
     ```
   - Create
6. Note le **Client ID** et le **Client secret** (popup ou icône copie)

### b) Côté Supabase

1. https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/auth/providers
2. Trouve **Google** dans la liste → toggle **Enable**
3. Colle ton **Client ID** et **Client Secret**
4. **Save**

✅ Test : depuis ton app, clique le bouton "Continuer avec Google" → ça doit ouvrir une webview Google → après login, tu reviens dans l'app connecté.

---

## 2. Facebook OAuth (~15 min)

### a) Côté Meta for Developers

1. Va sur https://developers.facebook.com/apps
2. **Create App** → cas d'usage : **Authenticate and request data from users with Facebook Login** → Next
3. Type : **Consumer**
4. Nom : `Correctis` → Create app
5. Dans le dashboard de l'app, **Add product → Facebook Login → Set up**
6. **Facebook Login → Settings** dans le menu de gauche :
   - **Valid OAuth Redirect URIs** : ajoute
     ```
     https://nqwymypfykiengbqdqim.supabase.co/auth/v1/callback
     ```
   - **Save changes**
7. **Settings → Basic** :
   - Note **App ID** et **App Secret** (clic sur "Show")
   - Renseigne **Privacy Policy URL** et **User Data Deletion** (URL bidon temporairement pour le dev, ex : `https://example.com/privacy`)
   - **Save changes**
8. En haut, passe l'app de **"In development"** à **"Live"** (toggle vert) — sinon seuls les développeurs peuvent se connecter

### b) Côté Supabase

1. https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/auth/providers
2. Trouve **Facebook** → toggle **Enable**
3. Colle **App ID** (Client ID) et **App Secret** (Client Secret)
4. **Save**

---

## 3. LinkedIn OAuth (~15 min)

### a) Côté LinkedIn Developer

1. Va sur https://www.linkedin.com/developers/apps
2. **Create app**
   - App name : `Correctis`
   - LinkedIn Page : ta page (ou crée-en une rapidement)
   - Privacy policy URL : `https://example.com/privacy` (temporaire)
   - App logo : upload n'importe quel logo
   - Legal agreement : coche
   - Create app
3. Onglet **Auth** :
   - **Authorized redirect URLs** : ajoute
     ```
     https://nqwymypfykiengbqdqim.supabase.co/auth/v1/callback
     ```
   - Note le **Client ID** et **Client Secret**
4. Onglet **Products** :
   - Demande l'accès à **Sign In with LinkedIn using OpenID Connect** (validation instantanée)
   - Demande l'accès à **Share on LinkedIn** (optionnel)

### b) Côté Supabase

1. https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/auth/providers
2. Cherche **LinkedIn (OIDC)** → toggle **Enable**
3. Colle **Client ID** et **Client Secret**
4. **Save**

---

## 4. Instagram — Pourquoi on le laisse de côté

Mauvaise nouvelle : **Instagram n'est plus utilisable pour la connexion tierce** en 2026.

- L'**Instagram Basic Display API** a été dépréciée et fermée par Meta en décembre 2024
- L'API qui la remplace (**Instagram Login**) ne sert qu'à connecter des comptes business à des outils Meta, pas pour de l'authentification tiers
- **Supabase n'a pas de provider Instagram natif** dans son catalogue

**Solution conseillée** :
- Garde Facebook (qui couvre techniquement les utilisateurs Instagram via leur compte Meta)
- L'icône Instagram peut rester dans l'UI mais elle redirige vers Facebook OAuth, OU on la retire

Dis-moi ce que tu préfères : retirer Instagram du footer, ou faire pointer son bouton vers Facebook.

---

## 5. Deep linking : à configurer côté Android pour que le callback revienne dans l'app

Quand l'utilisateur termine son login sur Google/FB/LinkedIn, Supabase redirige vers
`correctis://login-callback`. Pour que Android sache que cette URL doit ouvrir Correctis :

Édite `android/app/src/main/AndroidManifest.xml` — dans la balise `<activity>` de MainActivity, ajoute :

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="correctis" android:host="login-callback" />
</intent-filter>
```

Puis rebuild complet (`q` puis `flutter run`).

---

## Récapitulatif "minimum viable" pour le démo client

Si tu veux faire vite pour montrer ça au client :
1. **Google uniquement** (le plus simple, 10 min) — c'est ce qu'utilisent 80% des profs
2. Le code retirer ou cacher Facebook/LinkedIn/Instagram pour la démo
3. Tu pourras tout brancher pour la prod ensuite

Sinon, Google + Facebook + LinkedIn couvrent l'essentiel.
