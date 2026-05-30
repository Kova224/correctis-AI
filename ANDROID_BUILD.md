# Build de production Android — Correctis

Objectif : générer un fichier **`.aab`** (Android App Bundle) signé, prêt à
être publié sur le Google Play Store.

---

## 1. Créer la clé de signature (une seule fois, à conserver précieusement)

La clé de signature identifie ton app de façon unique. **Si tu la perds, tu ne
pourras plus jamais mettre à jour ton app sur le Play Store.** Sauvegarde-la.

Dans un terminal, lance (adapte le chemin si besoin) :

```powershell
keytool -genkey -v -keystore "$env:USERPROFILE\correctis-upload-key.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias correctis
```

> `keytool` est fourni avec Java. Si la commande n'est pas reconnue, utilise
> le chemin complet, par exemple :
> `& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey ...`

On va te demander :
- Un **mot de passe pour le keystore** (note-le)
- Ton nom, organisation, ville, pays (tu peux mettre des infos simples)
- Confirme avec `oui`

Résultat : un fichier `correctis-upload-key.jks` dans ton dossier utilisateur.

---

## 2. Créer le fichier `android/key.properties`

Crée un fichier **`android/key.properties`** (il est déjà dans `.gitignore`,
donc jamais commité — c'est voulu, c'est secret) avec ce contenu :

```properties
storePassword=TON_MOT_DE_PASSE_KEYSTORE
keyPassword=TON_MOT_DE_PASSE_KEYSTORE
keyAlias=correctis
storeFile=C:/Users/Bienvenu/correctis-upload-key.jks
```

Remplace :
- `TON_MOT_DE_PASSE_KEYSTORE` par le mot de passe choisi à l'étape 1
- `storeFile` par le chemin réel du `.jks` (utilise des **/** pas des **\\**)

> ⚠️ Ne commite JAMAIS ce fichier ni le `.jks` sur GitHub.

---

## 3. Vérifier la version de l'app

Dans `pubspec.yaml`, ligne `version:` — exemple :

```yaml
version: 1.0.0+1
```

- `1.0.0` = versionName (visible par l'utilisateur)
- `+1` = versionCode (entier, doit augmenter à CHAQUE upload sur le Play Store)

Pour la prochaine mise à jour : `1.0.1+2`, puis `1.1.0+3`, etc.

---

## 4. Générer le build

```powershell
flutter clean
flutter pub get
flutter build appbundle --release
```

Le fichier généré se trouve dans :
```
build/app/outputs/bundle/release/app-release.aab
```

C'est CE fichier `.aab` que tu uploades sur le Play Store.

> Pour tester l'APK directement sur un téléphone (hors store) :
> `flutter build apk --release`
> → `build/app/outputs/flutter-apk/app-release.apk`

---

## 5. Publier sur le Google Play Store

1. Crée un compte développeur : https://play.google.com/console/signup
   - Frais uniques : **25 $** (à vie)
2. Dans la Play Console : **Créer une application**
3. Remplis la fiche :
   - Nom : Correctis
   - Description courte + longue
   - **Captures d'écran** (au moins 2, format téléphone)
   - Icône 512×512 (ton logo)
   - Image de bannière 1024×500
   - Catégorie : Éducation
4. **Politique de confidentialité** : URL obligatoire (page web simple — je peux
   t'en générer une si besoin)
5. Questionnaire sur le contenu, public cible, etc.
6. Onglet **Production → Créer une release** → upload du `.aab`
7. Soumets pour examen (validation Google : quelques heures à 3 jours)

---

## Checklist avant publication

- [ ] Clé de signature créée et **sauvegardée** (cloud + disque externe)
- [ ] `key.properties` rempli
- [ ] `applicationId` = `com.correctis.app` (déjà fait ✓)
- [ ] Icône de l'app en place (déjà fait ✓)
- [ ] Permissions caméra justifiées dans le manifest (déjà fait ✓)
- [ ] App testée sur un vrai téléphone Android
- [ ] OCR + correction IA testées (facturation Google activée)
- [ ] Politique de confidentialité en ligne
- [ ] `flutter build appbundle --release` réussit sans erreur

---

## Rappel iOS

Publier sur l'App Store nécessite **un Mac** (pour compiler) + un compte
**Apple Developer** (99 $/an). Sans Mac, la version iOS reste en attente.
Alternative : services de build cloud (Codemagic, etc.) — à voir plus tard.
