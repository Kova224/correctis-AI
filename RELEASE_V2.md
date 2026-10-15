# Mise en production V2 — Correctis 1.0.12+14

Guide de déploiement étape par étape. Suivre **dans l'ordre**. Chaque
commande est à exécuter dans le terminal depuis le dossier
`correctis_app/`.

> **Pré-requis** : Flutter installé, `supabase` CLI installée
> (`npm install -g supabase`), accès au projet Supabase Correctis,
> accès Play Console Correctis, compte Resend (à créer si pas encore fait).

---

## 1. Mise à jour des packages Flutter

```bash
cd correctis_app
flutter clean
flutter pub get
```

**Nouveaux packages ajoutés** (récupérés automatiquement) :

- `app_links: ^6.3.2` — gestion des deep-links `correctis://`
- `pdf: ^3.11.1` + `printing: ^5.13.4` — génération bulletins PDF
- `flutter_local_notifications: ^17.2.3` + `timezone: ^0.9.4` —
  notifications locales (rappels prof / quota / invitations)

---

## 2. Push des migrations Supabase

Les **deux** nouvelles migrations à appliquer.

> **Note** : si tu utilises PowerShell, n'écris JAMAIS les chevrons `< >`
> littéralement — ils sont réservés pour la redirection. Tout ce qui est
> entre chevrons dans ce guide est un placeholder à remplacer par la
> vraie valeur (sans les chevrons).

### Cas A — projet déjà linké (probable)

Si tu as déjà poussé des migrations avant, ton projet est encore linké.
Tape simplement :

```powershell
supabase db push
```

### Cas B — première fois ou re-link nécessaire

1. Récupère ta **Reference ID** sur le Dashboard Supabase :
   https://supabase.com/dashboard → projet Correctis →
   **Project Settings → General → Reference ID**
   (chaîne de 20 caractères, ex : `abcdefghijklmnopqrst`)
2. Puis :

```powershell
supabase login
supabase link --project-ref abcdefghijklmnopqrst
supabase db push
```

> Remplace `abcdefghijklmnopqrst` par ta vraie Reference ID.

Migrations appliquées :

- `20260612000001_establishments.sql` — tables `establishments`,
  `establishment_members`, `establishment_invitations` + RLS strict +
  trigger auto-admin + RLS cross-table.
- `20260612000002_establishment_config.sql` — colonne `config JSONB`
  sur `establishments` (trimestres / coefficients / prefs).

Pour vérifier que ça a passé :

```bash
supabase db remote list
# Ou directement dans le Dashboard Supabase → Database → Migrations
```

---

## 3. Compte Resend + secrets Supabase

### 3a. Créer le compte Resend

1. Aller sur https://resend.com → **Sign up** (gratuit, 3 000 emails/mois).
2. **Domains** → ajouter `correctis.app` et suivre les instructions DNS
   (ajouter les enregistrements TXT/MX/CNAME donnés par Resend).
   - Si tu n'as pas le domaine prêt, utilise le domaine de test
     `onboarding@resend.dev` pour les premiers tests.
3. **API Keys** → **Create API Key** → permission **Sending access** →
   nommer "correctis-prod" → copier la clé `re_xxxxxxxx...`.

### 3b. Ajouter les secrets dans Supabase

Dashboard Supabase → **Project Settings** → **Edge Functions** →
**Secrets** → **Add new secret** (×3) :

| Nom                 | Valeur                                                                          |
|---------------------|---------------------------------------------------------------------------------|
| `RESEND_API_KEY`    | La clé `re_xxxxxxxx...` copiée à l'étape précédente                             |
| `RESEND_FROM_EMAIL` | `Correctis <noreply@correctis.app>` (ou `onboarding@resend.dev` pour tester)    |
| `APP_PUBLIC_URL`    | `https://correctis.app` (ou la landing page si elle existe)                     |

> Les autres secrets (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`) sont
> injectés automatiquement par Supabase, rien à faire.

---

## 4. Déployer la nouvelle Edge Function

```bash
supabase functions deploy send-invitation-email
```

Vérification :

```bash
supabase functions list
# Doit lister send-invitation-email comme déployée
```

Pour tester c'est plus simple via l'app directement (cf. section 7
checklist). Pas besoin de curl manuel.

---

## 5. Build & upload du 1.0.12+14 sur Play Console

```bash
flutter build appbundle --release
```

Le fichier généré : `build/app/outputs/bundle/release/app-release.aab`

**Upload sur Play Console** :

1. https://play.google.com/console → Correctis → **Test interne** (les
   12 testeurs actuels sont là)
2. **Créer une version** → upload `app-release.aab`
3. Coller le changelog (voir section suivante)
4. **Examiner la version** → **Déployer sur le test interne**

---

## 6. Changelog Play Console (à copier-coller)

### Version courte (notes de mise à jour, ≤ 500 caractères)

```
Correctis v1.0.12 — Vue Admin Établissement

• Comptes école : invitations enseignants par email, casier numérique
  centralisé, analytique pédagogique
• Configuration trimestres et coefficients matières
• Export bulletin PDF élève + Excel global du casier
• Langue choisissable : Français / English / العربية
• Notifications locales : copies prêtes, invitations, quota
• Stabilité et corrections d'erreurs
```

### Version détaillée (release notes Play Console)

```
NOUVEAU — Vue Admin Établissement
• Inviter des enseignants par email avec lien sécurisé 48h
• Casier numérique : toutes les notes de l'école, filtres classes/matières
• Recherche d'un élève + parcours scolaire complet
• Analytique : tendances, matières en difficulté, recommandations IA
• Paramètres école : trimestres, coefficients matières

EXPORTS
• Bulletin PDF stylé d'un élève (toutes matières + moyenne pondérée)
• Excel global du casier (filtrable par classe / matière)

PERSONNALISATION
• Langue : Français, English, العربية (changement immédiat)
• Notifications : copies corrigées, invitations en attente, quota gratuit
• Confidentialité et audit log paramétrables

INFRASTRUCTURE
• Système de notifications locales (aucune donnée n'est envoyée à un
  serveur de notifications)
• Tout l'admin établissement branché sur la base réelle
```

---

## 7. Checklist post-déploiement

À vérifier manuellement sur ton téléphone après installation :

- [ ] Login normal fonctionne (prof solo)
- [ ] Création d'examen + scan + IA → toujours OK
- [ ] Bouton "Vue Admin Établissement" **invisible** pour un prof solo
- [ ] Avec un compte admin école : bouton visible, l'AdminHomeScreen ouvre
- [ ] Inviter un enseignant → email reçu en moins d'une minute
- [ ] Cliquer le bouton de l'email → l'app ouvre l'AcceptInvitationScreen
- [ ] Acceptation → le user devient membre teacher de l'école
- [ ] Configurer trimestres + coefficients → sauvegarde OK
- [ ] Casier élève : bouton "EXPORTER LE BULLETIN PDF" → partage OK
- [ ] Casier global : bouton "EXCEL" → fichier .xlsx partageable
- [ ] Changer la langue → tout l'écran rebascule immédiatement
- [ ] Notifications : toggles changent en live, permissions Android demandées

---

## 8. Rollback si problème

Le keystore et la signature étant les mêmes que v1.0.11, on peut revenir
en arrière côté Play Console :

1. Play Console → Test interne → **Versions** → sélectionner v1.0.11+13
2. **Promouvoir cette version** (ou simplement la republier en interne).
3. Côté Supabase : les migrations sont **additives** (pas de DROP), donc
   les tables existantes ne sont pas affectées. Si besoin de désactiver
   la Vue Admin sans rollback :
   ```sql
   -- À exécuter dans Supabase SQL Editor
   update public.establishment_members set is_active = false;
   ```
   Cela masque la Vue Admin pour tous les comptes sans rien casser.

---

## 9. Tâches qui restent ouvertes après cette mise en prod

- **#54** : Validation Google Play (les 12 testeurs / 14 jours)
- **#57** : Solde 1000 TND à recevoir après livraison
- **#78** : Sprint 3 Moneroo (abonnement réel — reste en "bientôt")
- **#59 / #60** : Phase 1 (Moneroo) + Phase 2 (École v1) du contrat

Tout le reste du V2 est **production-ready**. Bonne mise en prod.
