-- =============================================================================
-- CORRECTIS V2 — Configuration pédagogique de l'établissement
-- =============================================================================
-- Ajoute une colonne `config` JSONB sur `establishments` pour stocker :
--   • Les dates des trimestres (T1/T2/T3) — saisies par l'école
--   • Les coefficients des matières (Maths=4, Français=3, etc.)
--   • Les préférences de notification au niveau école
--
-- Stockage en JSONB pour rester flexible sans multiplier les tables.
-- Schéma attendu :
--   {
--     "terms": [
--       { "name": "Trimestre 1", "start": "2025-09-15", "end": "2025-12-20" },
--       { "name": "Trimestre 2", "start": "2026-01-05", "end": "2026-03-28" },
--       { "name": "Trimestre 3", "start": "2026-04-13", "end": "2026-06-30" }
--     ],
--     "coefficients": {
--       "Mathématiques": 4,
--       "Physique-Chimie": 3,
--       "Français": 4
--     },
--     "notifications": {
--       "alerts": true,
--       "invitations_reminders": true,
--       "anonymous_stats": false
--     }
--   }
-- =============================================================================

alter table public.establishments
  add column if not exists config jsonb not null default '{}'::jsonb;

-- Index GIN pour les recherches éventuelles dans la config
create index if not exists establishments_config_gin_idx
  on public.establishments using gin (config);

-- Helper : récupérer la config d'un établissement (utilisé côté admin uniquement)
-- Les RLS existantes sur `establishments` couvrent déjà l'accès.
