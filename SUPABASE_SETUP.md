# Setup GitHub + Supabase pour Correctis

## 1. Initialiser Git et pousser sur GitHub

Dans un terminal **ouvert dans le dossier `correctis_app/`** :

```powershell
git init
git add .
git commit -m "Initial commit — Correctis MVP"
git branch -M main
```

Crée un repo vide sur GitHub (https://github.com/new) — par exemple `correctis-app` — **sans README, sans .gitignore, sans licence** (vide). Ensuite :

```powershell
git remote add origin https://github.com/<TON_USERNAME>/correctis-app.git
git push -u origin main
```

> Si Git te demande des credentials : utilise un **Personal Access Token** (Settings GitHub → Developer settings → Personal access tokens → Tokens classic → repo scope).

À chaque modification du code, tu pousseras avec :

```powershell
git add .
git commit -m "Description du changement"
git push
```

---

## 2. Connecter Supabase à GitHub (auto-sync des migrations)

Dans le dashboard Supabase (https://supabase.com/dashboard) :

1. Ouvre ton projet **Correctis**
2. Va dans **Settings → Integrations → GitHub Integration**
3. Clique **Connect Repository**
4. Autorise Supabase à accéder à ton repo `correctis-app`
5. Choisis :
   - **Production branch** : `main`
   - **Migrations directory** : `supabase/migrations`
6. **Enable Auto-deploy** ✅

Désormais, **à chaque `git push` sur `main`**, Supabase applique automatiquement les nouvelles migrations SQL dans ton schéma.

---

## 3. Récupérer les clés Supabase

Dans le dashboard Supabase :

1. **Settings → API**
2. Note ces deux valeurs (à me transmettre ou à mettre dans un `.env`) :
   - **Project URL** — `https://xxxxxxxxxxxxx.supabase.co`
   - **Anon / Public key** — `eyJhbGc...` (longue chaîne)

> ⚠️ La clé **service_role** est **secrète** : ne la mets JAMAIS dans l'app mobile, ni sur GitHub. Elle est réservée à un éventuel backend.

---

## 4. Premier déploiement du schéma

À ton premier `git push`, Supabase exécutera automatiquement le fichier
`supabase/migrations/20260516000001_initial_schema.sql`.

Ça crée :
- 6 tables (`profiles`, `exams`, `questions`, `sub_questions`, `student_copies`, `question_grades`)
- 3 buckets de Storage (`subjects`, `copies`, `avatars`)
- Row Level Security (chaque prof ne voit que ses données)
- Trigger d'auto-création du profil à l'inscription

Tu peux vérifier dans le dashboard :
- **Table Editor** → tu dois voir les 6 tables
- **Storage** → tu dois voir les 3 buckets
- **Authentication → Policies** → tu dois voir les policies RLS

---

## 5. Activer la connexion sociale (optionnel, à faire dans le dashboard)

Pour Google Sign-In :
1. **Authentication → Providers → Google → Enable**
2. Crée un OAuth Client ID sur https://console.cloud.google.com
3. Renseigne `Client ID` et `Client Secret`

Idem pour Facebook (Meta for Developers) et LinkedIn (LinkedIn Developer Portal).

---

## 6. Prochaines étapes (côté code Flutter)

Quand le repo est en place et les clés transmises, on :
1. Ajoute `supabase_flutter` au `pubspec.yaml`
2. Initialise Supabase dans `main.dart` avec l'URL et la clé anon
3. Crée `lib/services/supabase_auth_service.dart` (remplace `AuthService` mock)
4. Crée `lib/services/supabase_exam_service.dart` (remplace `ExamService` mock)
5. Branche le storage pour les images

Les écrans Flutter ne changeront pas — seules les implémentations des services sont remplacées.

---

## Workflow quotidien après setup

```powershell
# Modifie le code Flutter
# Test : flutter run

# Quand satisfait :
git add .
git commit -m "feat: ajout de la fonctionnalité X"
git push

# → Supabase synchronise les migrations SQL automatiquement
# → GitHub conserve l'historique
```

Pour modifier le schéma DB, crée un nouveau fichier daté dans
`supabase/migrations/` (ex: `20260520000001_add_column_x.sql`), puis push.
Supabase l'applique automatiquement.
