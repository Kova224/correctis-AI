# Setup OAuth — Google uniquement

Pour activer la connexion **"Continuer avec Google"** dans l'app :
1. Créer une application OAuth dans Google Cloud Console
2. Coller le Client ID + Secret dans Supabase
3. Ajouter un intent-filter dans AndroidManifest pour le callback

**Callback URL Supabase** :

```
https://nqwymypfykiengbqdqim.supabase.co/auth/v1/callback
```

---

## 1. Côté Google Cloud Console

1. Va sur https://console.cloud.google.com/
2. Si tu n'as pas encore de projet : crée-en un, ex. `Correctis`
3. Active l'API requise :
   - **APIs & Services → Library** → cherche **Google+ API** ou **People API** → **Enable**
4. **APIs & Services → OAuth consent screen** :
   - User Type : **External** → Create
   - App name : `Correctis`
   - User support email : ton email
   - Developer contact : ton email
   - Save → Save → Save → Back to Dashboard
5. **APIs & Services → Credentials** :
   - **+ Create Credentials → OAuth client ID**
   - Application type : **Web application**
   - Name : `Correctis Supabase`
   - **Authorized redirect URIs** : ajoute exactement :
     ```
     https://nqwymypfykiengbqdqim.supabase.co/auth/v1/callback
     ```
   - **Create**
6. Une popup t'affiche le **Client ID** et le **Client Secret** — copie-les.

---

## 2. Côté Supabase

1. https://supabase.com/dashboard/project/nqwymypfykiengbqdqim/auth/providers
2. Trouve **Google** dans la liste → toggle **Enable**
3. Colle **Client ID** et **Client Secret**
4. **Save**

---

## 3. Côté Android — deep link de retour

Pour qu'après le login Google le navigateur ramène l'utilisateur dans l'app,
édite `android/app/src/main/AndroidManifest.xml` — dans la balise `<activity>`
de MainActivity, ajoute :

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="correctis" android:host="login-callback" />
</intent-filter>
```

Puis rebuild complet : `q` puis `flutter run`.

---

## Test

Depuis l'app :
1. Clique **"Continuer avec Google"** sur l'écran de login
2. Une webview Google s'ouvre → choisis ton compte Google
3. Tu es redirigé vers l'app, connecté

Logs en cas de problème : terminal VS Code (ligne `Login error` ou `AuthException`).
