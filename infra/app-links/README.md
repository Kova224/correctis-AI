# Android App Links — liens d'invitation en https

Les invitations enseignants s'ouvrent maintenant aussi par `https://correctis.app/invite?token=…` (App Link vérifié), en plus de l'ancien `correctis://invite?token=…`. Une autre app ne peut pas intercepter un App Link vérifié.

La connexion Google reste en `correctis://login-callback`. Elle est protégée par PKCE : un code intercepté est inutilisable sans le secret gardé par l'app.

## À faire une fois

1. Dans Play Console → Correctis → **Intégrité de l'app** → **Signature d'application**, copier l'**empreinte du certificat SHA-256** de la clé de signature de l'app.
2. Coller cette empreinte dans `assetlinks.json` (dans ce dossier), à la place de `REMPLACER_…`.
3. Publier le fichier à l'adresse exacte `https://correctis.app/.well-known/assetlinks.json` (type `application/json`, pas de redirection).
4. Sur la même adresse, servir une page `/invite` qui dit « Ouvrez ce lien depuis votre téléphone Android avec Correctis installé ». C'est ce que voit quelqu'un qui n'a pas l'app.
5. Dans Supabase → Edge Functions → Secrets, mettre `APP_LINKS_ENABLED` = `1` : le bouton de l'e-mail d'invitation utilisera alors le lien https.
6. Vérifier sur un téléphone : `adb shell pm get-app-links com.correctis.app` doit afficher `correctis.app: verified`.

Tant que l'étape 3 n'est pas faite, rien ne casse. Le lien https s'ouvre dans le navigateur, et l'e-mail garde le lien `correctis://` comme bouton principal.

Si le domaine n'est pas `correctis.app`, remplacer l'hôte dans `android/app/src/main/AndroidManifest.xml` (intent-filter `autoVerify`) et dans `lib/services/deep_link_service.dart` (`_appLinkHosts`).
