# Déploiement CinetPay Aurore (v1) — Sandbox & Production

Ce document décrit comment déployer le système Pay-as-you-go d'EduCorrect/Correctis
avec **CinetPay Aurore v1** — l'API actuelle de CinetPay (`https://api.cinetpay.net`).

> Référence métier : `EduCorrect — Concept et fonctionnement du système Pay-as-you-go` (juin 2026)

> ⚠️ **Règle de sécurité absolue** — Aucune des valeurs suivantes ne doit jamais
> apparaître dans un chat, un email non chiffré, un screenshot public ou un commit Git :
> `CINETPAY_API_KEY`, `CINETPAY_SECRET_KEY` (mot de passe API),
> `service_role_key` Supabase, ou tout token JWT commençant par `eyJ`.
> Ces valeurs vivent uniquement dans : (a) la console CinetPay, (b) Supabase Studio → Secrets.

---

## 1. Prérequis

- **Compte CinetPay** (Sandbox ou Production) actif. Pour Correctis Guinée, le
  compte est rattaché au **pays GN** et à la **devise GNF**.
- Sur la console CinetPay :
  - **API Key** récupérée depuis Ressources → API & sécurité (clique 👁 pour voir).
  - **Mot de passe API défini** (bouton "Définir un mot de passe API" sur la même page).
    Sans ça, l'authentification OAuth `/v1/oauth/login` est impossible.
- **Aucune installation CLI nécessaire** : tout se fait via Supabase Studio
  (navigateur).
- Le projet Supabase est lié au projet Correctis (URL `https://<ref>.supabase.co`).

> Aurore n'utilise **pas** de `site_id` (contrairement à l'ancienne API v2). Le
> compte est identifié par le couple `api_key` + `api_password`.

---

## 2. Configuration des 6 secrets Supabase

Via **Supabase Studio → Settings → Edge Functions → onglet Secrets → "Add new secret"** :

| Nom du secret (exact) | Valeur à mettre |
|---|---|
| `CINETPAY_API_KEY` | API Key (Ressources → API & sécurité → 👁 → copier) |
| `CINETPAY_SECRET_KEY` | Le "Mot de passe API" que vous avez défini |
| `CINETPAY_NOTIFY_URL` | `https://<ref>.supabase.co/functions/v1/cinetpay-webhook` |
| `CINETPAY_RETURN_URL` | `https://correctis.app/payment-return` (page de courtoisie) |
| `CINETPAY_ENV` | `TEST` (Sandbox) ou `PROD` (production) |
| `CINETPAY_COUNTRY` | `GN` — **repli uniquement** depuis la grille v5 : le pays vient maintenant de la commande (`payment_orders.country_code`) |

**Remplacer `<ref>`** par votre ref de projet Supabase (visible dans l'URL du
Studio : `https://supabase.com/dashboard/project/<REF>`).

### Grille v5 (sept. 2026) : pays et devise par compte

Depuis la grille tarifaire v5, chaque compte choisit son **pays de facturation**
(Bénin, Burkina Faso, Côte d'Ivoire, Mali, Niger, Sénégal, Togo → **XOF** ;
Guinée → **GNF**). La commande stocke `amount`, `amount_currency` et
`country_code`, et `cinetpay-init-payment` construit `payment_method` avec le
pays de la commande (`OM_CI`, `MTN_GN`, `WAVE_SN`…). La carte bancaire
(`VISA_<PAYS>`) est refusée en GNF.

⚠️ Le compte marchand CinetPay doit être **activé pour les pays XOF** (et pas
seulement la Guinée) avant d'accepter des paiements en XOF.

### Pourquoi `CINETPAY_COUNTRY` existait

L'API Aurore exige le format `<OPERATEUR>_<PAYS>` pour `payment_method` :
`OM_GN` (Orange Guinée), `MTN_GN`, `WAVE_GN`, `MOOV_GN`, `VISA_GN` (carte).
Notre Edge Function `cinetpay-init-payment` lit `CINETPAY_COUNTRY` et concatène
automatiquement (l'app mobile envoie juste le code court `OM`, `MTN`, etc.).

### Codes pays supportés

| Pays | `CINETPAY_COUNTRY` | Opérateurs Mobile Money disponibles |
|---|---|---|
| 🇬🇳 Guinée | `GN` | Orange, MTN |
| 🇨🇮 Côte d'Ivoire | `CI` | Orange, MTN, Moov, Wave |
| 🇸🇳 Sénégal | `SN` | Orange, Free, Expresso, Wave |
| 🇲🇱 Mali | `ML` | Orange, Moov |
| 🇧🇫 Burkina Faso | `BF` | Orange, Moov, Wave |
| 🇨🇲 Cameroun | `CM` | Orange, MTN |
| 🇧🇯 Bénin | `BJ` | MTN, Moov |
| 🇹🇬 Togo | `TG` | Moov, Togocell |
| 🇨🇩 RD Congo | `CD` | Orange, Airtel, Mpesa, Africell |
| 🇳🇪 Niger | `NE` | Airtel |

---

## 3. Déploiement des 3 Edge Functions via Supabase Studio

Pour chacune des 3 fonctions ci-dessous, faire :

1. **Supabase Studio → Edge Functions → "Deploy a new function"**
2. Nom : exactement celui indiqué (sinon l'app ne trouvera pas la fonction)
3. Ouvrir dans Windows le fichier `index.ts` correspondant, sélectionner tout
   (Ctrl+A), copier (Ctrl+C), coller dans l'éditeur de code Studio (Ctrl+V)
4. Cliquer **"Deploy"** ou **"Deploy function"** → attendre "Deployed successfully"
5. Vérifier via le bouton **"Test"** en haut à droite (voir section 6)

| Nom de la fonction | Fichier source | Verify JWT |
|---|---|---|
| `cinetpay-init-payment` | `supabase/functions/cinetpay-init-payment/index.ts` | ✅ Activé (appelée par l'app) |
| `cinetpay-webhook` | `supabase/functions/cinetpay-webhook/index.ts` | ❌ **Désactivé** (appelée par CinetPay sans JWT) |
| `expire-credits-cron` | `supabase/functions/expire-credits-cron/index.ts` | ❌ **Désactivé** (appelée par pg_cron) |

⚠️ Pour désactiver Verify JWT après création : Edge Functions → la fonction →
**Settings** → décocher "Verify JWT with legacy secret" → Save.

### URLs publiques générées (à mémoriser)

```
https://<ref>.supabase.co/functions/v1/cinetpay-init-payment
https://<ref>.supabase.co/functions/v1/cinetpay-webhook
https://<ref>.supabase.co/functions/v1/expire-credits-cron
```

La valeur de `CINETPAY_NOTIFY_URL` (secret) doit **exactement** correspondre à
l'URL publique de `cinetpay-webhook`.

---

## 4. Pousser la migration SQL

1. Supabase Studio → **SQL Editor** → "New query"
2. Ouvrir dans Windows :
   `supabase/migrations/20260621000001_credits_payg.sql`
3. Copier tout → coller dans l'éditeur → **Run**
4. Si erreur "function already exists with different return type" → ouvrir aussi
   `supabase/migrations/20260622000001_credits_payg_fix.sql` et l'exécuter pour
   appliquer le fix incrémental (DROP + recréation des fonctions modifiées,
   ajout des colonnes GNF + cinetpay_notify_token).

### Vérification rapide

```sql
-- Doit retourner 12 lignes (12 packs)
select code, name, price_fcfa, price_gnf from public.credit_packs order by display_order;

-- Doit montrer les colonnes amount_gnf, cinetpay_notify_token, etc.
select column_name from information_schema.columns
where table_schema='public' and table_name='payment_orders'
order by ordinal_position;
```

---

## 5. Planification du CRON d'expiration quotidien

Tous les jours à 00h01 UTC, les lots dont `expires_at < now()` doivent passer en
statut `expired`. Pour ça, on utilise `pg_cron` côté Postgres (plus fiable que
d'appeler l'Edge Function depuis un service externe).

Dans **SQL Editor** :

```sql
-- Active pg_cron (déjà activé sur la plupart des projets Supabase)
create extension if not exists pg_cron;

-- Planifie le job
select cron.schedule(
  'expire-credits-job',
  '1 0 * * *',                          -- 00:01 UTC tous les jours
  $$ select public.expire_credits_job() $$
);

-- Vérifier
select * from cron.job;
select * from cron.job_run_details order by start_time desc limit 5;
```

> Alternative si `pg_cron` n'est pas disponible : utiliser un service externe
> (cron-job.org, EasyCron) qui appelle quotidiennement l'Edge Function
> `expire-credits-cron` avec un header `Authorization: Bearer <service_role_key>`.
> Mais `pg_cron` est plus simple.

---

## 6. Test rapide des Edge Functions après déploiement

Sur la page de chaque fonction, en haut à droite : bouton **"Test"**.

### Test 1 — `cinetpay-init-payment`

- Method : `POST`
- Body :
  ```json
  { "order_id": "00000000-0000-0000-0000-000000000000", "payment_method": "OM" }
  ```
- ✅ Réponse attendue : **HTTP 401 "Session invalide"**
  (normal : pas de JWT dans le test, la validation auth marche)
- ❌ HTTP 404 → fonction pas réellement déployée, refaire l'étape 3

### Test 2 — `cinetpay-webhook`

- Method : `POST`
- Body : `{}`
- ✅ Réponse attendue : **HTTP 200 "ok"** (le webhook accepte tout et répond
  toujours 200 pour ne pas déclencher de retry CinetPay)

### Test 3 — `expire-credits-cron`

- Method : `POST`
- Body : (vide)
- ✅ Réponse attendue : **HTTP 200** avec `{"ok": true, "expired_count": 0, ...}`

---

## 7. Test bout-en-bout du flux paiement Sandbox

Une fois les Edge Functions déployées et le CRON planifié :

1. Build l'app Flutter avec la dernière version (`flutter build appbundle --release`)
2. Upload sur **Google Play Console → Test interne → Créer une version**
3. Envoyer le lien d'invitation au testeur (Michel)
4. Sur le téléphone testeur :
   - Profil → "Mes crédits" → "+ Acheter des crédits"
   - Choisir un pack (recommandé : **Solo S** = 2 200 FCFA, plus petit pour tester)
   - Choisir **Orange Money** → "Payer 2 200 FCFA"
5. La page CinetPay hosted s'ouvre dans le navigateur
6. **Saisir un numéro de test Sandbox CinetPay Guinée** :

### Numéros de test Sandbox Guinée (Orange Money)

| Numéro de test | Scénario |
|---|---|
| `+224 622220700` | ✅ **Succès immédiat** (à utiliser pour la démo) |
| `+224 622220701` | ⏳ Pending puis succès (~10 s) |
| `+224 622220703` | ❌ Échec immédiat |
| `+224 622220704` | ⏳❌ Pending puis échec |
| `+224 622220706` | 🔁 Pending infini (pour tester le timeout 5 min) |

### Carte VISA de test (si paiement par carte)

| Numéro | Expiration | CVV | Résultat |
|---|---|---|---|
| `4093 1917 6621 6474` | `12/30` | `123` | ✅ Succès |
| `4663 2959 4278 4758` | `12/30` | `123` | ❌ Échec |

7. Après validation du paiement, CinetPay frappe notre webhook → la RPC
   `complete_payment_order` crée le `credit_lot` correspondant.
8. Le testeur revient dans l'app → écran "**Paiement confirmé**" + solde mis à jour.

---

## 8. Surveillance & logs pendant les tests

Pendant qu'un testeur paye, garder ouverts en parallèle :

- **Edge Functions → `cinetpay-init-payment` → Logs** : doit afficher
  `[cinetpay-init] login OK` puis `init OK` quand le testeur clique Payer.
- **Edge Functions → `cinetpay-webhook` → Logs** : doit afficher
  `[webhook] paiement confirmé en XXXms` quand le testeur valide le paiement.
- **SQL Editor** avec cette requête prête :
  ```sql
  select id, status, amount_fcfa, amount_gnf,
         cinetpay_transaction_id, cinetpay_notify_token, paid_at, failure_reason
  from payment_orders
  order by created_at desc limit 5;
  ```
  Doit montrer `status='completed'` et `paid_at` rempli sur le dernier ordre.

### Erreurs courantes & fixes

| Symptôme | Cause | Fix |
|---|---|---|
| Logs init : `CinetPay non configuré` | Un secret manque | Vérifier les 6 secrets dans Settings → Edge Functions |
| Logs init : `login KO` | Mauvais `CINETPAY_API_KEY` ou `CINETPAY_SECRET_KEY` | Re-copier depuis la console CinetPay |
| Logs init : `payment_method invalide` | `CINETPAY_COUNTRY` manquant ou faux | Vérifier la valeur (`GN` pour la Guinée) |
| Logs init : `currency mismatch` | Le compte CinetPay n'est pas en GNF | Vérifier côté console CinetPay |
| 404 sur les Edge Functions | Pas vraiment déployées ou quota Supabase dépassé | Refaire le Deploy + vérifier Settings → Usage |
| Webhook non appelé après paiement | URL webhook fausse côté CinetPay ou Storage saturé | Vérifier `CINETPAY_NOTIFY_URL` exact |

---

## 9. Passage en Production (après validation Sandbox)

1. Demander à CinetPay (`activations@cinetpay.com`) la **réduction du délai de
   reversement à 2-3 jours** (réduit le besoin de trésorerie de pont).
2. Récupérer les **vraies clés Production** dans la console CinetPay (compte Prod).
3. Mettre à jour les 6 secrets Supabase :
   - `CINETPAY_API_KEY` ← nouvelle valeur Prod
   - `CINETPAY_SECRET_KEY` ← nouveau mot de passe API Prod
   - `CINETPAY_ENV` ← passer à `PROD`
   - Les 3 autres restent identiques.
4. Re-déployer les 3 Edge Functions (le code est identique, seuls les secrets
   changent — il suffit de relancer un Deploy sans modifier le code).
5. Sur la console CinetPay Prod, configurer l'URL webhook si demandé.
6. Activer le **rechargement automatique** sur Anthropic Console (seuil 30 €,
   recharge à 130 €) avec la carte VISA PayCard comme moyen de paiement
   (cf. document "Concept Pay-as-you-go" sections 6 et 7).

---

## 10. Aide-mémoire URLs & ressources

| Ressource | URL |
|---|---|
| API CinetPay Aurore | `https://api.cinetpay.net` |
| Console marchand CinetPay | `https://panel.cinetpay.net` |
| Doc API CinetPay | Ressources → Documentation API (depuis la console) |
| Support CinetPay (réduction délai reversement) | `activations@cinetpay.com` |
| Supabase Studio (votre projet) | `https://supabase.com/dashboard/project/<ref>` |
| Init paiement | `https://<ref>.supabase.co/functions/v1/cinetpay-init-payment` |
| Webhook | `https://<ref>.supabase.co/functions/v1/cinetpay-webhook` |
| CRON expiration | `https://<ref>.supabase.co/functions/v1/expire-credits-cron` |

---

## 11. Checklist finale avant publication Play Store

- [ ] 6 secrets configurés dans Supabase (vérification visuelle dans Settings)
- [ ] 3 Edge Functions déployées et testées (chacune retourne le bon statut au bouton Test)
- [ ] Migration SQL `20260621000001_credits_payg.sql` exécutée
- [ ] (si applicable) Migration fix `20260622000001_credits_payg_fix.sql` exécutée
- [ ] CRON `pg_cron` `expire-credits-job` planifié et vérifié dans `cron.job`
- [ ] Mot de passe API défini côté console CinetPay
- [ ] URL webhook CinetPay correspond exactement à `CINETPAY_NOTIFY_URL`
- [ ] App Flutter buildée avec la dernière version (vérifier le footer du Profil)
- [ ] AAB uploadé sur Play Console Test Interne
- [ ] Testeur (Michel) ajouté à la liste des testeurs internes
- [ ] Test sandbox passé avec `+224 622220700` → "Paiement confirmé" + solde +N crédits

---

## 12. Rappel sécurité — checklist

- [ ] Aucun fichier `*.env` ou `secrets.yaml` commité dans Git (`.gitignore` à jour)
- [ ] `CINETPAY_API_KEY` et `CINETPAY_SECRET_KEY` jamais collés dans un chat, mail, ou screenshot
- [ ] `service_role_key` Supabase utilisé uniquement côté Edge Functions (jamais dans l'app Flutter)
- [ ] Tokens JWT (`eyJ...`) jamais partagés en clair
- [ ] La whitelist IP CinetPay (Ressources → API & sécurité) reste **vide** en
      Sandbox ; en Production, whitelister uniquement les IPs sortantes Supabase
      si CinetPay l'exige (sinon laisser vide aussi)
