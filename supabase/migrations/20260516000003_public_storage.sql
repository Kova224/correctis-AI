-- =============================================================================
-- CORRECTIS — Buckets publics pour permettre à Claude vision de fetch les URLs
-- =============================================================================
-- Bascule les buckets `subjects` et `copies` en public.
-- La sécurité : les chemins contiennent un UUID aléatoire impossible à deviner.
-- L'écriture/suppression reste protégée par les policies RLS sur storage.objects.
-- =============================================================================

update storage.buckets set public = true where id = 'subjects';
update storage.buckets set public = true where id = 'copies';

-- Policies SELECT publiques.
-- Postgres ne supporte pas "create policy if not exists", on drop d'abord.
drop policy if exists "Public read subject files" on storage.objects;
drop policy if exists "Public read copy files"    on storage.objects;

create policy "Public read subject files" on storage.objects
  for select using (bucket_id = 'subjects');

create policy "Public read copy files" on storage.objects
  for select using (bucket_id = 'copies');
