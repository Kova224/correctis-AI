# Publier Correctis sur le Play Store — guide pas à pas

## Prérequis (à faire avant)

- [x] Build `.aab` généré (`build/app/outputs/bundle/release/app-release.aab`)
- [x] Clé de signature sauvegardée (`correctis-upload-key.jks` dans `C:\Users\Bienvenu\` + backup cloud)
- [x] Politique de confidentialité en ligne (https://kova224.github.io/correctis-AI/privacy.html)
- [ ] Captures d'écran préparées (voir `SCREENSHOTS_GUIDE.md`)
- [ ] Feature graphic 1024×500 prêt
- [ ] Icône 512×512 prête

---

## 1. Créer ton compte développeur Google Play

1. Va sur https://play.google.com/console/signup
2. Connecte-toi avec ton compte Google
3. Choisis **Type de compte** : "Personnel" (ou "Organisation" si tu as une société)
4. Paie les **25 $** (frais uniques à vie)
5. Vérifie ton identité (photo de ta carte d'identité — délai 1 à 5 jours pour validation)

> Le compte développeur est validé sous quelques jours. Tu peux commencer à
> préparer ta fiche pendant ce temps, mais tu ne pourras pas soumettre tant
> que le compte n'est pas approuvé.

---

## 2. Créer l'application dans Play Console

Une fois ton compte validé :

1. Dans Play Console → **Toutes les applications** → **Créer une application**
2. Remplis :
   - **Nom de l'application** : `Correctis — Correction IA`
   - **Langue par défaut** : Français
   - **Type d'app** : App
   - **Gratuite ou payante** : Gratuite
   - Accepte les déclarations de Play Store
3. Clique **Créer**

---

## 3. Configurer la fiche du store

Dans le menu de gauche : **Présence sur le Store → Présentation principale du Store**

Colle les textes depuis [PLAY_STORE_LISTING.md](PLAY_STORE_LISTING.md) :
- Nom (court)
- Description courte
- Description longue
- Upload icône 512×512
- Upload feature graphic 1024×500
- Upload au moins 2 captures d'écran (jusqu'à 8)

**Save**.

---

## 4. Catégorisation et tags

Menu de gauche : **Présence sur le Store → Catégorisation et tags**

- Catégorie : **Éducation**
- Tags : éducation, école, enseignant, correction
- Coordonnées :
  - Email : ton email (publié sur la fiche, garde-en un dédié genre `correctis.app@gmail.com`)
  - Site web : laisse vide ou ton GitHub Pages
  - Téléphone : optionnel

---

## 5. Politique de confidentialité

Menu : **Politique → Confidentialité**

- URL : `https://kova224.github.io/correctis-AI/privacy.html`

---

## 6. Sécurité des données (Data safety)

Menu : **Politique → Sécurité des données**

Suis le formulaire :
- Tu collectes ? **Oui**
- Données chiffrées en transit ? **Oui**
- Suppression possible ? **Oui** (tu acceptes les demandes de suppression par email)
- Types de données : Email, Nom, Photos, Mot de passe
- Usage : Authentification, fonctionnalité de l'app
- Partage avec tiers : Anthropic (pour la correction IA)

Détails complets dans [PLAY_STORE_LISTING.md](PLAY_STORE_LISTING.md) section "Privacy declaration".

---

## 7. Questionnaire de classification (Content Rating)

Menu : **Politique → Classification du contenu**

Réponds **Non** à tout sauf "Informations personnelles collectées" (Oui).

→ Classification probable : **PEGI 3 / Tout public**

---

## 8. Public cible et contenu

Menu : **Politique → Public cible**

- Tranche d'âge ciblée : **18+** (ton app vise les enseignants adultes)
- Cible-t-elle des enfants ? **Non**

---

## 9. Uploader le build (.aab)

Menu : **Production** → **Créer une release**

1. Clique **Choose signing key** → laisse Google gérer (option par défaut "Use Google-generated key")
2. **App bundles** → Upload → choisis ton fichier :
   `C:\Users\Bienvenu\Documents\Corrector AI\Correctis AI\correctis_app\build\app\outputs\bundle\release\app-release.aab`
3. **Release name** : `1.0.0` (auto-rempli depuis pubspec)
4. **Notes de version** :
   ```
   Première version de Correctis.

   - Correction automatique de copies par IA (Claude Vision)
   - Tableau de bord avec statistiques
   - Classement par classe + export Excel
   - Compatible avec tous types d'examens et 7 langues
   ```
5. Clique **Save**

---

## 10. Lancer le déploiement

Onglet **Vue d'ensemble** ou **Production** :

1. Vérifie que toutes les sections ont un ✓ vert
2. Si des sections sont en orange/rouge → clique dessus, corrige
3. Clique **Send for review** / **Envoyer pour examen**

⏳ **Délai de validation Google** : 3 heures à 3 jours pour une première soumission.

Tu reçois un email quand l'app est **acceptée** (ou refusée, avec la raison).

---

## 11. Après publication

Une fois l'app publiée sur le Play Store :

- URL publique : `https://play.google.com/store/apps/details?id=com.correctis.app`
- Tu peux la partager aux profs
- Tu suivras les téléchargements / avis dans Play Console → **Statistics**

---

## Stratégie recommandée : déploiement progressif

Plutôt que de publier d'un coup à 100%, fais un **rollout progressif** :

1. Dans la release Production → **Country availability** → **Add 1 country** → choisis **Sénégal** (ton marché test)
2. **Rollout percentage** : commence à **20%**
3. Surveille les crashs / avis pendant 3-4 jours
4. Si tout va bien → augmente à 50% puis 100%
5. Étends ensuite à d'autres pays francophones (France, Côte d'Ivoire, etc.)

Ça évite qu'un bug critique touche tes 1000 premiers users d'un coup.

---

## En cas de rejet Google

Google peut refuser l'app si :
- Politique de confidentialité absente / incorrecte
- Permissions non justifiées dans la fiche
- App qui plante au lancement
- Manque de fonctionnalités (rare)

Le mail de rejet explique le problème → tu corriges → tu re-soumets gratuitement.

---

## Récap : ce qu'il te reste à faire

1. [ ] Faire valider ton compte Play Console (1-5 jours)
2. [ ] Prendre 4-6 captures d'écran depuis l'émulateur
3. [ ] Créer le feature graphic 1024×500 (Canva)
4. [ ] Activer GitHub Pages pour la politique (voir `docs/README.md`)
5. [ ] Pousser le code sur GitHub (`git push`) pour que GitHub Pages publie
6. [ ] Remplir la fiche Play Console
7. [ ] Uploader le `.aab`
8. [ ] Soumettre pour examen

---

Bon courage ! Si tu bloques à n'importe quelle étape, dis-le-moi.
