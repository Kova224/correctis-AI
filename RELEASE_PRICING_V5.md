# Mise en production — Grille tarifaire v5 (Correctis 1.0.64+71)

Source : « EduCorrect — Grille tarifaire v5, Septembre 2026 » (Michel).
Remplace la grille v4 et toute tarification antérieure.

## Ce qui change

| Sujet | Avant | Grille v5 |
|---|---|---|
| Prix | Une grille GNF + « ≈ F CFA » converti | Deux grilles **autonomes** XOF et GNF, aucune conversion affichée |
| Devise | Tout le monde en GNF | Pays de facturation choisi par le compte → XOF (BJ, BF, CI, ML, NE, SN, TG) ou GNF (GN), verrouillé après le 1er paiement |
| Consommation | 1 copie = 1 crédit | 1 crédit = jusqu'à 8 pages : 1–8 p. = 1, 9–17 = 2, 18–25 = 3, 26–34 = 4, puis +1 / ≈ 8-9 pages |
| Affichage | — | Crédits affichés avant le lancement (écran de scan + fiche copie) |
| Échec technique | Remboursement côté serveur cassé en mode async | Crédits remis en solde par `grade-copy` (idempotent, multi-lots) |
| Zones illisibles (HITL) | Re-débitait 1 crédit | Incluse, 0 crédit |
| Quota prof (école) | En copies | En crédits réellement débités |
| Carte bancaire | Proposée partout | Désactivée tant que CinetPay n'a pas activé l'option carte (`VISA_<PAYS>`) sur le compte marchand. Pour l'ouvrir : secret `CINETPAY_CARD_ENABLED` = 1 et `cardEnabled: true` dans `infra/web/credits/config.js` |
| Opérateurs | Les 5 partout | Selon le pays (cf. `lib/models/billing.dart`) |

Les colonnes « Marge » du PDF sont internes : elles ne sont pas affichées dans l'app.

## Déploiement (dans l'ordre)

```powershell
cd correctis_app
supabase migration list # seules les 5 migrations 20261015* doivent manquer côté Remote
supabase db push        # 20261015000001 (grille v5) + …02 (sécurité) + …03 (points ouverts) + …04 (suppression de compte) + …05 (achat web) + …06 (pas de pack solo pour un compte admin)
supabase functions deploy cinetpay-init-payment
supabase functions deploy cinetpay-webhook --no-verify-jwt     # appelée par CinetPay, sans JWT
supabase functions deploy grade-copy
supabase functions deploy extract-questions
supabase functions deploy generate-answer-key
supabase functions deploy send-invitation-email
supabase functions deploy expire-credits-cron --no-verify-jwt  # appelée par pg_cron
supabase functions deploy cleanup-orphan-copies
supabase functions deploy delete-account
flutter clean
flutter pub get
flutter analyze         # doit sortir sans erreur avant le build
flutter build appbundle --release                  # 1.0.64+71
```

Ordre important : migrations → Edge Functions → build de l'app. `grade-copy`
appelle la nouvelle RPC `authorize_grading` : la déployer avant la migration
casserait les corrections.

`expire-credits-cron` et `cleanup-orphan-copies` refusent désormais tout appel
qui n'a pas la clé service_role (ou l'en-tête `x-cron-secret` = secret
`CRON_SECRET`). Si le planificateur les appelle avec la clé anon, mettre à jour
sa configuration (Supabase → Edge Functions → Schedules / pg_cron).

### Réglages hors code (à faire une fois)

1. **Proxy CinetPay en HTTPS** : suivre `infra/cinetpay-proxy/README.md`, puis changer le mot de passe API CinetPay. En `CINETPAY_ENV=PROD`, un proxy en `http://` est maintenant refusé.
2. **Confirmation d'e-mail** : Supabase → Authentication → Providers → Email → activer « Confirm email ». Le pack Découverte n'est accordé qu'après confirmation.
3. **App Links (invitations en https)** : suivre `infra/app-links/README.md`. Puis mettre le secret `APP_LINKS_ENABLED=1`.
4. **Clé de signature** : le build release échoue désormais si `android/key.properties` manque. Il n'y a plus de signature debug silencieuse.
6. **Page d'achat web (option B)** : publier `infra/web/credits/`, mettre `CINETPAY_RETURN_URL` et `CINETPAY_FAILED_URL` sur son adresse, et ajouter cette adresse dans les Redirect URLs de Supabase Auth. Voir `infra/web/README.md`.
5. **Suppression de compte** : publier `infra/web/supprimer-compte.html`, renseigner son URL dans la Play Console (Sécurité des données → Suppression des données) et ajouter le paragraphe fourni à la politique de confidentialité. Voir `infra/web/README.md`.

Le bucket `copies` devient **privé** (migration 20261015000003). Les anciennes versions de l'app n'affichent plus les photos des copies, qui apparaissent cassées. Il faut donc publier la 1.0.64 et demander aux testeurs de mettre à jour.

La migration est idempotente, et elle affiche à la fin le tableau des prix par pack (XOF, GNF, prix par copie) pour contrôle.

Les anciennes versions de l'app continuent à fonctionner : `reserve_credit` et `refund_credit` délèguent au nouveau barème. L'achat leur est en revanche refusé tant que le compte n'a pas de pays (`BILLING_COUNTRY_REQUIRED`). Il faut donc mettre l'app à jour.

## À valider côté CinetPay avant la prod

1. Le compte marchand est actuellement en Guinée : il faut **activer les pays XOF** dans la console CinetPay.
2. Codes opérateurs vérifiés le 15/10/2026 avec le tableau « Méthodes de paiement » de CinetPay. Ajoutés : Moov au Niger, Free Money au Sénégal, T-Money au Togo. Ils sont définis à trois endroits qui doivent rester identiques : `OPERATORS_BY_COUNTRY` dans `supabase/functions/cinetpay-init-payment/index.ts`, `COUNTRIES` dans `infra/web/credits/app.js` et `BillingCountry` dans `lib/models/billing.dart`.
2 bis. Demander à CinetPay d'activer le **paiement par carte** (Visa/Mastercard, méthode `VISA_<PAYS>`) sur le compte marchand. Sans cette activation, CinetPay répond « payment method invalide ».
3. La commission CinetPay (hypothèse de 2,5 %) et le coût Supabase sont des hypothèses du PDF à confirmer. Ils ne changent rien au code.

## Correctifs de l'audit du 15/10/2026 (inclus dans cette version)

- Écran « Mon abonnement » remplacé par la carte « Mes crédits » ; plus aucun texte « abonnement / sans limite / essai gratuit » dans l'app.
- Crédits gratuits illimités (remise à zéro de `discovery_used`) : bloqué.
- Inscription sauvage comme prof d'une école, notes injectées dans le casier d'une autre école : bloqué.
- Corrections sans payer en appelant `grade-copy` directement : bloqué (`authorize_grading`).
- `extract-questions`, `expire-credits-cron`, `cleanup-orphan-copies` ouverts à tous : verrouillés.
- `cleanup-orphan-copies` pouvait supprimer des copies valides au-delà de 1 000 copies : corrigé.
- Listing public des copies d'élèves dans le stockage : retiré.
- Force brute des identifiants prof : 10 essais par heure.
- Permission Android `READ_MEDIA_IMAGES` retirée (politique Play « Photos et vidéos »).
- Données du compte précédent affichées après un changement de compte : corrigé.
- Copies d'élèves : bucket privé, liens signés d'1 h dans l'app et de 15 min pour l'IA.
- Proxy CinetPay : https obligatoire en production (Caddyfile fourni).
- Pack Découverte : accordé seulement après confirmation de l'e-mail.
- Option C « Génération IA » : vrai corrigé généré par Claude (`generate-answer-key`), 5 par examen et par 24 h.
- Notes figées 3 jours après publication au casier (base + interface).
- Build release : échoue sans clé de signature.
- Paiement refusé : détecté tout de suite par l'écran de paiement.
- Badge d'accueil : quota école affiché pour les profs rattachés.
- Invitations : App Link https vérifié en plus de `correctis://`.
- Option B (Google Play) : l'app ne vend plus de crédits. Plus d'écran de packs ni de paiement, plus de prix ni de bouton « Acheter », et les messages ne disent plus d'acheter. L'achat se fait sur la page web `infra/web/credits/`, avec CinetPay comme avant.
- Suppression de compte (exigence Google Play) : bouton dans le Profil et les Réglages admin, suppression définitive après 30 jours (annulable en se reconnectant), purge chaque nuit par `expire-credits-cron`, page web pour les demandes sans l'app.

## Checklist de test

- [ ] Nouveau compte prof : à l'ouverture de « Choisir un pack », le choix du pays s'affiche.
- [ ] Côte d'Ivoire : Solo S = 875 FCFA (29 FCFA / copie), Orange, MTN, Moov, Wave et Carte proposés.
- [ ] Guinée : Solo S = 13 500 GNF (450 GNF / copie), Orange et MTN seulement, avec la mention « Carte indisponible en GNF ».
- [ ] Après un paiement confirmé, le bouton « Changer » de pays disparaît.
- [ ] Copie de 11 pages : l'écran de scan affiche « 2 crédits », et le solde baisse de 2.
- [ ] Copie de 9 pages avec 1 seul crédit restant : message « nécessite 2 crédits, il vous en reste 1 ».
- [ ] Correction en échec : les crédits reviennent dans le solde (historique : « Remboursement »).
- [ ] Relance des zones illisibles : aucun crédit débité.
- [ ] Prof d'école : le quota diminue du nombre de crédits de la copie.
- [ ] Profil (prof solo) : carte « Mes crédits » avec le solde, plus de « Mon abonnement ».
- [ ] Déconnexion puis connexion avec un autre compte : examens, crédits et école du nouveau compte (rien de l'ancien).
- [ ] Rejoindre une école avec email + identifiant : OK ; 10 mauvais identifiants : message « Trop de tentatives ».
- [ ] Import du sujet (extraction IA) et correction d'une copie : toujours OK après le déploiement des Edge Functions.
- [ ] Photos des copies visibles dans la fiche copie et l'écran de scan. Un lien copié depuis la base (`/object/public/copies/...`) doit renvoyer une erreur dans un navigateur.
- [ ] Option C : « Générer » produit un corrigé complet. La 6e génération dans la journée affiche « Limite atteinte ».
- [ ] Copie publiée depuis plus de 3 jours : le crayon affiche « Notes figées ».
- [ ] Paiement annulé ou refusé sur CinetPay : message de refus, pas d'attente de 5 min.
- [ ] Nouveau compte e-mail : 0 crédit avant confirmation, 3 crédits après le clic sur le lien.
- [ ] Prof d'école : le badge d'accueil affiche « École : N crédits · perso : M ».
- [ ] Dans l'app, aucun écran ni message ne parle d'acheter. Vérifier « Mes crédits », le profil, l'accueil, la carte crédits admin, les quotas profs et le chatbot (« combien ça coûte »).
- [ ] Page web : se connecter avec un compte prof, choisir le pays, prendre Micro, payer en Sandbox. Au retour, « Paiement confirmé » s'affiche et le solde augmente dans l'app.
- [ ] Page web avec un compte admin : seuls les packs école s'affichent. Avec 2 écoles, choisir la 2e : les crédits arrivent dans son pool.
- [ ] Page web, paiement annulé sur CinetPay : « Paiement non abouti ».
- [ ] Profil → Supprimer mon compte : le bouton reste grisé tant que l'e-mail n'est pas retapé. Après validation, l'app affiche la date de suppression puis déconnecte.
- [ ] Reconnexion pendant les 30 jours : l'écran « Suppression du compte prévue » apparaît. « Annuler la suppression » ramène à l'accueil.
- [ ] Admin seul d'une école : l'écran explique que la suppression est impossible et propose le support.
- [ ] Test complet : `select * from admin_request_account_deletion('test@…', 0);`, puis appeler `delete-account`. Le compte disparaît, ses photos aussi. Les notes d'école restent visibles dans le casier admin, et le paiement reste sans nom.
