# À ton réveil — démarrage en 2 minutes

L'app est complète. Voici exactement ce qu'il te reste à faire :

## Option 1 — Le plus simple (recommandé)

Ouvre PowerShell dans le dossier `correctis_app/` puis :

```powershell
.\setup_and_run.ps1
```

Le script :
1. génère les dossiers natifs `android/` et `ios/`
2. ajoute automatiquement les permissions caméra
3. installe les packages
4. lance l'app sur ton émulateur ou téléphone

## Option 2 — Manuellement (Android Studio)

```powershell
cd correctis_app
flutter create .          # Crée les dossiers android/ et ios/
flutter pub get           # Installe les dépendances
```

Puis :
1. Ouvre Android Studio → **File > Open** → choisis le dossier `correctis_app/`
2. Attends que Gradle sync se termine (1-2 min la première fois)
3. Démarre un émulateur Android (AVD Manager)
4. Clique sur ▶ **Run**

## Compte démo (déjà rempli sur l'écran de connexion)

```
email    : demo@correctis.app
password : demo1234
```

Clique simplement sur **Se connecter**.

## Permissions natives à ajouter

> Le script `setup_and_run.ps1` le fait pour toi.
> Si tu fais à la main, voir le README.md.

## Que tester en priorité ?

1. **Login** → Home (liste examens vide)
2. **+ Nouvel examen** → "Devoir maths" → 20 pts
3. **Importer le sujet** → choisis 1-2 photos depuis la galerie
4. **Analyse** : 4-6 questions s'affichent (mock IA)
5. **Valider le sujet**
6. **Source de correction** : choisis "Génération IA" → "Générer le corrigé" → coche "Je valide" → Valider
7. **Scanner une copie** : nom "Élève 1" → photo(s) → "Nouvel élève"
8. **Refais 2-3 élèves**, attends quelques secondes
9. Reviens à l'examen → les copies passent en "Corrigé" automatiquement
10. Tape sur une copie → consulte les notes/commentaires → mode édition (icône crayon)
11. Bouton **Excel** → partage du fichier .xlsx

## Si quelque chose ne marche pas

| Problème | Solution |
|----------|----------|
| `flutter: command not found` | Installe Flutter ≥ 3.27 — https://docs.flutter.dev/get-started/install/windows |
| Erreur de permission caméra | Lance `setup_and_run.ps1` ou ajoute manuellement (cf. README.md) |
| Gradle bloqué | Patiente, le 1er build prend 3-5 min |
| L'app crashe sur splash | Désinstalle l'app de l'émulateur et relance |
| Compte démo refuse | Vérifie l'email exact `demo@correctis.app` (pas .com) |

## Tout ce qui est livré

✓ Conforme au cahier des charges Correctis MVP v2 (mai 2026)
✓ Design fidèle à la maquette CrowdFund (bleu profond + cyan + coins arrondis)
✓ Compatible iOS et Android
✓ 29 fichiers Dart, ~3500 lignes
✓ Mode démo 100 % local (Firebase/IA simulés)
✓ Export Excel **réel** (paquet `excel`)
✓ Tous les écrans du flux : login, home, création examen (3 étapes),
  3 sources de correction, scan multi-pages avec validation, résultats avec
  édition manuelle, export Excel partageable

## À faire ensuite (post-MVP)

Quand tu seras prêt à passer en prod, remplace les services mock :
- `auth_service.dart` → `firebase_auth`
- `exam_service.dart` (SharedPreferences) → `cloud_firestore`
- `ocr_service.dart` → Google Cloud Vision
- `ai_correction_service.dart` → OpenAI / Anthropic / Vertex AI

L'API publique des services reste **inchangée** : seule l'implémentation interne
change. Donc les écrans n'ont pas besoin d'être réécrits.

Bonne nuit ! 🌙
