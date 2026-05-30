# Captures d'écran pour le Play Store

Google demande **au minimum 2 captures**, mais **4 à 8 est recommandé** pour
maximiser tes téléchargements.

## Spécifications requises

- **Téléphone** : 320×569 minimum, 3 840×3 840 maximum
- Format **PNG** ou **JPEG**
- Ratio entre **9:16 et 16:9**
- Idéal : **1080×1920** (pile la résolution du Pixel 7 émulateur)

---

## Captures à prendre (l'ordre est important)

Ces 6 écrans racontent ton produit dans l'ordre :

### 1. Login / Splash — "Bienvenue"
Le splash bleu avec le logo, ou l'écran de login propre. **Première impression** = identité visuelle.

### 2. Dashboard d'accueil — "Tableau de bord complet"
Avec stats (X copies / Y%), grille d'actions rapides, graphique des meilleurs élèves.
→ Pour ce screenshot, crée d'abord **2-3 examens fake** avec quelques copies corrigées, sinon le dashboard est vide.

### 3. Création d'examen — "Importez votre sujet"
L'écran d'import du sujet avec une photo de page apparente ou la validation des questions extraites.

### 4. Scan de copie — "Scannez les copies"
L'écran de scan en cours avec quelques pages dans la galerie thumbnails.

### 5. Détail copie corrigée — "L'IA corrige pour vous"
Une copie avec notes par question + commentaires de l'IA visibles.

### 6. Classement — "Podium des meilleurs élèves"
L'écran de classement avec le podium top 3 médailles or/argent/bronze.

---

## Comment prendre les captures depuis l'émulateur Android

### Méthode 1 — Bouton de capture intégré (le plus simple)

1. Dans la fenêtre de l'émulateur Pixel 7, à droite il y a une barre d'outils
2. Clique l'icône **appareil photo** 📷 (Take screenshot)
3. La capture est automatiquement sauvée dans `C:\Users\Bienvenu\Desktop\Screenshot_*.png`

### Méthode 2 — Raccourci clavier

- Pendant que l'émulateur a le focus : **Ctrl + S** (Windows) → sauvegarde la capture

### Méthode 3 — En ligne de commande

```powershell
adb shell screencap -p /sdcard/screen.png
adb pull /sdcard/screen.png ./screenshot.png
```

---

## Astuces pour des captures qui convertissent

✅ **Désactive la barre de statut Android** : tu vois l'horloge système + batterie en haut. Tu peux la masquer pour un rendu plus pro.

```powershell
adb shell settings put global policy_control immersive.full=*
# Pour réactiver : adb shell settings put global policy_control null
```

✅ **Mets des données réalistes** : pas "Test 1", "Test 2" — utilise des vrais noms et titres d'examens crédibles.
- Examen : "Devoir de mathématiques — Chapitre 3"
- Élèves : "Diop Awa", "Ndiaye Mamadou", "Faye Aissatou"
- Notes variées (15, 12, 18, 9…)

✅ **Heure de la barre de statut** : règle l'émulateur sur **9:41** (clin d'œil iPhone) ou **12:00**, ça fait pro.

✅ **Batterie 100% / réseau plein** dans la barre du haut (par défaut dans l'émulateur).

✅ **Évite le clavier ouvert** quand tu prends la capture.

---

## Feature graphic (1024×500)

C'est l'image bannière en haut de ta fiche Play Store. Obligatoire.

Trois options pour la créer :

### Option A — Canva (gratuit, 5 min)
1. Va sur https://www.canva.com/
2. Crée un design **1024 × 500 px** (custom size)
3. Mets :
   - Fond bleu Correctis (#2E4BC7)
   - Ton logo à gauche
   - Texte "Correctis — Correction IA pour Profs" à droite
   - Optionnel : capture d'écran réduite à droite
4. Télécharge en PNG

### Option B — Figma (gratuit)
Pareil que Canva, version plus pro.

### Option C — Image générée par IA
Demande à ChatGPT/Claude/Midjourney : "Crée une bannière 1024x500 pour mon app éducative Correctis, fond bleu #2E4BC7, style moderne et professionnel, texte 'Correctis - Correction IA pour Profs'"

---

## Icône haute résolution (512×512)

Tu l'as déjà — c'est `assets/icon/app_icon.png` ! Mais Google la veut en 512×512.

Si ton `app_icon.png` est plus grand (1024×1024 par exemple) :
- Redimensionne-le en 512×512 via Paint, Photoshop, ou en ligne sur https://www.iloveimg.com/resize-image
- Sauvegarde sous `play-store-icon-512.png`

---

## Récap des assets à préparer

| Asset | Dimensions | Source |
|---|---|---|
| Icône Play Store | 512 × 512 px | Redimensionné depuis `app_icon.png` |
| Feature graphic | 1024 × 500 px | À créer (Canva) |
| Capture 1 (Login) | 1080 × 1920+ | Émulateur |
| Capture 2 (Dashboard) | 1080 × 1920+ | Émulateur (avec data) |
| Capture 3 (Création) | 1080 × 1920+ | Émulateur |
| Capture 4 (Scan) | 1080 × 1920+ | Émulateur |
| Capture 5 (Correction) | 1080 × 1920+ | Émulateur |
| Capture 6 (Classement) | 1080 × 1920+ | Émulateur |

Stocke tous ces fichiers dans un dossier `play-store-assets/` (ne le commit pas — c'est juste pour ta soumission).
