# Edge Function `send-invitation-email` — Setup

Cette fonction envoie l'email d'invitation aux enseignants quand un admin
établissement clique sur "Envoyer l'invitation".

## Pré-requis Resend

1. Créer un compte gratuit sur https://resend.com (3 000 emails/mois gratuits).
2. Vérifier un domaine (ex: `correctis.app`) ou utiliser le domaine de test
   `onboarding@resend.dev` pour les tests.
3. Générer une clé API : https://resend.com/api-keys → `Create API Key` →
   permission **Sending access**.

## Secrets à ajouter dans Supabase

Dashboard Supabase → **Project Settings** → **Edge Functions** → **Secrets** →
**Add new secret** pour chacun :

| Nom                 | Valeur                                                        |
|---------------------|---------------------------------------------------------------|
| `RESEND_API_KEY`    | Votre clé Resend (`re_xxxxxxx...`)                            |
| `RESEND_FROM_EMAIL` | `Correctis <noreply@correctis.app>` (ou `onboarding@resend.dev` pour tester) |
| `APP_PUBLIC_URL`    | `https://correctis.app` (ou votre URL marketing)              |

> Les secrets `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` sont injectés
> automatiquement par Supabase, vous n'avez rien à faire pour ceux-là.

## Déploiement

```bash
cd correctis_app
supabase functions deploy send-invitation-email
```

Ou via le dashboard Supabase : **Functions** → **Deploy a new function** →
copier-coller le contenu de `index.ts`.

## Test rapide

Une fois déployée, dans l'app Flutter :

1. Connectez-vous avec un compte admin d'un établissement.
2. Profil → **Vue Admin Établissement** → onglet **Enseignants** → bouton
   **Inviter un enseignant** → saisissez votre propre email.
3. Vous devez recevoir le mail dans la minute.
4. Cliquer le bouton "Accepter l'invitation" ouvre l'app sur l'écran
   `AcceptInvitationScreen` qui appelle `EstablishmentService.acceptInvitation()`.

## Sécurité

La fonction vérifie côté serveur que :
- Le caller est authentifié (JWT valide)
- Le caller est `admin` de l'établissement de l'invitation
- L'invitation n'est ni expirée (48h) ni déjà acceptée

Aucun token n'est exposé : seul l'URL `correctis://invite?token=XXX` est
envoyée à l'email, et le token est consommable une seule fois côté
`acceptInvitation`.
