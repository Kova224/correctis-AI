-- =============================================================================
-- Publication des copies au casier de l'établissement
-- =============================================================================
-- Ajoute `published_at` à `student_copies`. Une copie reste privée au prof
-- tant qu'elle n'est pas publiée. Le casier admin n'affiche que les copies
-- avec `published_at` non null.
--
-- Workflow :
--   1. Le prof corrige toutes les copies de l'examen (status = graded)
--   2. Il clique "Envoyer au casier" sur l'écran Résultats
--   3. Toutes les copies graded de cet examen reçoivent `published_at = now()`
--   4. L'admin voit ces notes dans son casier numérique avec le nom du prof
--
-- L'admin peut filtrer par prof + classe + matière, et exporter en PDF/Excel.
-- =============================================================================

alter table public.student_copies
  add column if not exists published_at timestamptz;

create index if not exists student_copies_published_at_idx
  on public.student_copies(published_at);
