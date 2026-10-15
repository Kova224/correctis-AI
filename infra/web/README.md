# Pages web publiques de Correctis

Site publié sur Netlify le 15/10/2026 : **https://correctis.netlify.app** (dépôt par Netlify Drop du dossier `infra/web`). Pour mettre à jour, redéposer le dossier entier dans Netlify (Deploys → glisser le dossier). Si le domaine `correctis.app` est rattaché plus tard, refaire les réglages 2 et 3 ci-dessous avec la nouvelle adresse.

| Page | Adresse | Rôle |
|---|---|---|
| `index.html` | `https://correctis.netlify.app/` | Présentation, tarifs, questions fréquentes |
| `credits/` (dossier entier) | `https://correctis.netlify.app/credits/` | Achat de crédits (option B) |
| `confidentialite.html` | `https://correctis.netlify.app/confidentialite.html` | Politique de confidentialité (URL à mettre dans la Play Console) |
| `supprimer-compte.html` | `https://correctis.netlify.app/supprimer-compte.html` | Suppression de compte (Google Play) |
| `404.html` | — | Page « introuvable » (utilisée automatiquement par Netlify) |

Le style commun est dans `assets/` : `site.css`, polices auto-hébergées (`assets/fonts/`, licence SIL OFL), logo. Les animations sont dans `assets/motion.css` (jetons de durée et de courbe, transitions entre pages, révélations au défilement) et `assets/motion.js` ; elles se coupent toutes seules si le visiteur a demandé « réduire les animations » sur son appareil. Les tarifs affichés sur l'accueil sont une copie de la grille v5 dans `assets/site.js` ; si la grille change en base, mettre ce fichier à jour.

Ce sont des fichiers statiques, sans serveur à faire tourner : un hébergement gratuit comme GitHub Pages, Netlify ou Cloudflare Pages suffit. Le site doit être en **https**.

## `credits/` : achat de crédits (option B)

Google Play interdit de vendre les crédits dans l'app sans passer par son propre système de paiement. Depuis le 15/10/2026, l'app ne vend donc plus rien : elle affiche le solde et l'historique, sans prix, sans bouton d'achat et sans lien vers cette page. Les crédits s'achètent ici, avec le même compte que dans l'app. La page fait le paiement CinetPay (Mobile Money, ou carte bancaire en FCFA).

Le parcours : connexion (e-mail + mot de passe, ou Google) → pays de facturation → pack « pour moi » ou « pour mon école » → moyen de paiement et numéro → page CinetPay → retour sur la page, qui affiche le résultat.

Les prix, la devise et les contrôles restent côté serveur : la page appelle `create_payment_order` puis l'Edge Function `cinetpay-init-payment`, et les crédits sont ajoutés par `cinetpay-webhook`, comme avant.

### Réglages (une fois)

1. **Publier** le dossier `credits/` entier : `index.html`, `app.js`, `styles.css`, `config.js` et `vendor/`.
2. **Secrets Supabase** (Edge Functions → Secrets) :
   - `CINETPAY_RETURN_URL` = `https://correctis.netlify.app/credits/` ;
   - `CINETPAY_FAILED_URL` = `https://correctis.netlify.app/credits/`.

   L'Edge Function ajoute elle-même `?order=<id>` à ces adresses.
3. **Supabase → Authentication → URL Configuration → Redirect URLs** : ajouter `https://correctis.netlify.app/credits/**`. Sans ça, la connexion Google sur la page renvoie vers l'app au lieu de la page.
4. Dans **Google Cloud Console → Identifiants → client OAuth « Web »** utilisé par Supabase, rien à changer : le retour Google passe toujours par `https://<projet>.supabase.co/auth/v1/callback`.

### Ce que l'app ne doit jamais faire (règle Google Play)

L'app ne doit ni mentionner cette page, ni afficher de prix, ni proposer de lien ou de bouton pour acheter. On peut en revanche en parler en dehors de l'app : site, WhatsApp, e-mails, affiches dans les écoles.


## `supprimer-compte.html` : suppression de compte

Google Play exige une page web où l'on peut demander la suppression de son compte sans l'app. Cela vaut aussi quand la suppression existe dans l'app.

1. Publié avec le reste du site : `https://correctis.netlify.app/supprimer-compte.html`.
2. Dans la Play Console, aller dans **Contenu de l'application → Sécurité des données → Suppression des données** :
   - « Les utilisateurs peuvent demander la suppression de leur compte » : **Oui** ;
   - URL : l'adresse de la page ci-dessus ;
   - « Les utilisateurs peuvent demander la suppression de certaines données sans supprimer leur compte » : **Non**.

## Traiter une demande reçue par e-mail

Une demande peut arriver à support@correctis.app. Vérifier qu'elle vient bien de l'adresse du compte, puis lancer dans **Supabase → SQL Editor** :

```sql
-- Délai standard de 30 jours :
select * from admin_request_account_deletion('email@du-compte.com');

-- Suppression au prochain passage du job de nuit :
select * from admin_request_account_deletion('email@du-compte.com', 0);
```

Si `out_blocker` vaut `SCHOOL_OWNER` ou `SOLE_ADMIN`, la personne gère une école : il faut d'abord régler l'école avec elle.

Pour supprimer tout de suite, sans attendre la nuit, appeler la fonction `delete-account` avec la clé service_role :

```bash
curl -X POST "https://<projet>.supabase.co/functions/v1/delete-account" \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>" -H "Content-Type: application/json" -d '{}'
```

## Texte à ajouter dans la politique de confidentialité

> **Suppression du compte et conservation des données.** Vous pouvez supprimer votre compte depuis l'application (Profil → Supprimer mon compte) ou en écrivant à support@correctis.app. La suppression devient définitive 30 jours après la demande ; vous pouvez l'annuler pendant ce délai en vous reconnectant. Sont alors supprimés : votre profil (nom, e-mail, téléphone, photo), les photos des copies et des sujets, vos examens et notes personnels, ainsi que vos crédits non utilisés. Sont conservés : les notes publiées pour une école, sans les photos, car elles font partie du dossier scolaire des élèves ; et les enregistrements de paiement (montant, date, pays, référence de transaction), détachés de votre identité, pour nos obligations comptables.
