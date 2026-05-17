# Correctis — App mobile (MVP)

Application Flutter pour la correction automatique de copies par IA.
Conforme au cahier des charges fonctionnel **Correctis MVP v2** (mai 2026).

> Compatible **iOS** et **Android** — Flutter ≥ 3.27.0.

---

## Démarrage rapide (3 commandes)

### Sur Windows (Android Studio / VS Code)

Ouvre un terminal **dans le dossier `correctis_app/`** et exécute :

```powershell
flutter create .                  # Génère les dossiers natifs android/ et ios/
flutter pub get                   # Installe les dépendances
flutter run                       # Lance l'app sur émulateur ou appareil
```

> **Compte démo pré-rempli** sur l'écran de connexion :
> `demo@correctis.app` / `demo1234` — clique simplement sur **Se connecter**.

### Ouvrir dans Android Studio

1. **File → Open** → sélectionne le dossier `correctis_app/`.
2. Attends que Gradle finisse de synchroniser (~2 min la première fois).
3. Choisis un émulateur Android dans le sélecteur de device (en haut à droite).
4. Clique sur le ▶ vert (Run).

### Ouvrir dans VS Code

1. **File → Open Folder** → `correctis_app/`.
2. Installe l'extension Flutter si demandé.
3. Appuie sur **F5** pour lancer.

---

## Mode démo

Cette version MVP fonctionne **entièrement en local**, sans Firebase :

- Auth simulée (SharedPreferences) — un compte démo est pré-créé.
- OCR simulé : génère 4–6 questions d'exemple à partir des images du sujet.
- IA simulée : produit des notes/commentaires plausibles par question.
- Persistance : SharedPreferences (les examens et copies sont sauvegardés
  entre deux ouvertures de l'app).

L'**export Excel est réel** (paquet `excel`) et utilise le partage natif
iOS/Android (paquet `share_plus`).

---

## Permissions natives

`flutter create .` génère les fichiers natifs. **Avant de lancer**,
ajoute les permissions caméra :

### Android — `android/app/src/main/AndroidManifest.xml`

Ajoute juste avant `<application>` :

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
```

Et dans `android/app/build.gradle`, vérifie :

```gradle
android {
    compileSdkVersion 34
    defaultConfig {
        minSdkVersion 23
        targetSdkVersion 34
    }
}
```

### iOS — `ios/Runner/Info.plist`

Ajoute dans `<dict>` :

```xml
<key>NSCameraUsageDescription</key>
<string>Correctis utilise l'appareil photo pour scanner les copies des élèves.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Correctis a besoin d'accéder à vos photos pour importer des sujets ou des copies.</string>
```

---

## Structure du projet

```
correctis_app/
├── pubspec.yaml
├── lib/
│   ├── main.dart                     # Point d'entrée + Providers
│   ├── theme/
│   │   └── app_theme.dart            # Palette CrowdFund (bleu + cyan)
│   ├── models/
│   │   ├── app_user.dart
│   │   ├── exam.dart
│   │   ├── question.dart
│   │   ├── copy.dart
│   │   └── correction_source.dart
│   ├── services/
│   │   ├── auth_service.dart         # Mock Firebase Auth
│   │   ├── exam_service.dart         # CRUD examens & copies + correction async
│   │   ├── ocr_service.dart          # Mock Google Cloud Vision
│   │   ├── ai_correction_service.dart# Mock LLM
│   │   └── export_service.dart       # Excel réel (paquet excel)
│   ├── widgets/
│   │   ├── rounded_header.dart       # Header bleu arrondi (style CrowdFund)
│   │   ├── primary_button.dart       # Bouton cyan arrondi
│   │   ├── custom_text_field.dart    # Inputs ronds
│   │   ├── exam_card.dart
│   │   ├── status_chip.dart
│   │   └── section_card.dart
│   └── screens/
│       ├── splash_screen.dart
│       ├── auth/
│       │   ├── login_screen.dart
│       │   └── register_screen.dart
│       ├── home/
│       │   └── home_screen.dart
│       ├── exam/
│       │   ├── create_exam_screen.dart       # Étape 1 (infos) + 2 (import sujet)
│       │   ├── subject_validation_screen.dart# Étape 3 (validation barème)
│       │   ├── correction_source_screen.dart # Source A / B / C
│       │   ├── exam_detail_screen.dart       # Vue centrale + export Excel
│       │   └── student_copy_detail_screen.dart
│       └── scan/
│           ├── new_student_screen.dart       # Saisie nom/PV
│           └── scan_session_screen.dart      # Scan multi-pages + validation
└── README.md
```

---

## Flux utilisateur (cf. cahier §2)

1. **Connexion** (compte démo pré-rempli)
2. **Créer un examen** : titre + classe + note totale
3. **Importer le sujet** : caméra ou galerie (multi-pages)
4. **Valider la structure** : questions et points (éditables, ajout/suppression)
5. **Source de correction** : A. corrigé type | B. cours | C. génération IA validée
6. **Scan des copies** : 1 élève = 1 session → multi-pages → "Terminer cette copie"
7. **Correction automatique** en arrière-plan (notification visuelle)
8. **Consultation/modification** des notes (éditables)
9. **Export Excel** depuis l'écran d'examen

---

## Brancher Firebase / OCR / IA en prod

Quand tu seras prêt à passer en mode production, remplace :

| Mock                                | Service de prod                          |
|-------------------------------------|------------------------------------------|
| `AuthService`                       | `firebase_auth`                          |
| `ExamService` (SharedPreferences)   | `cloud_firestore`                        |
| `OcrService`                        | `googleapis: vision/v1`                  |
| `AiCorrectionService`               | OpenAI / Anthropic / Vertex AI           |

Les interfaces des services sont **déjà conformes** à un usage Firebase /
LLM — tu n'auras qu'à remplacer l'implémentation, pas l'API exposée aux écrans.

---

## Design

Palette inspirée de la maquette CrowdFund fournie par le client :

- **Primary** : `#2E4BC7` (bleu profond)
- **Accent** : `#3DD4D4` (cyan boutons CTA)
- **Coins** : très arrondis (16-32 px)
- **Typographie** : Poppins (Google Fonts, chargée dynamiquement)
- **Headers** : bleu avec coins arrondis en bas
- **Boutons CTA** : pill (100 px de rayon) en cyan

---

## Dépannage

**Erreur `flutter create .` : pubspec already exists**
→ Normal, c'est exactement le but : générer android/ et ios/ sans toucher au reste.

**Erreur de permission caméra**
→ Tu n'as pas ajouté les permissions natives (voir section Permissions).

**Le compte démo ne se connecte pas**
→ Vérifie que tu utilises bien `demo@correctis.app` / `demo1234`.

**L'app crashe au démarrage**
→ Vérifie `flutter --version` ≥ 3.27 et `flutter doctor` n'a pas de [✗].

---

## Licence

Code créé pour le projet Correctis (client privé).
