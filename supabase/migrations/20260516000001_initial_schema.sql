-- =============================================================================
-- CORRECTIS — Schéma initial
-- Tables : profiles, exams, questions, sub_questions, student_copies, question_grades
-- + Row Level Security (chaque prof ne voit que ses données)
-- + Storage bucket pour les images de copies et sujets
-- =============================================================================

-- Extensions utiles
create extension if not exists "pgcrypto" with schema extensions;

-- =============================================================================
-- 1. PROFILES (extension de auth.users)
-- =============================================================================
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  email         text not null,
  display_name  text not null default '',
  photo_path    text,
  phone         text,
  school        text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.profiles is 'Profil étendu du professeur (1-1 avec auth.users).';

-- =============================================================================
-- 2. EXAMS
-- =============================================================================
create table if not exists public.exams (
  id                  uuid primary key default extensions.gen_random_uuid(),
  owner_id            uuid not null references auth.users(id) on delete cascade,
  title               text not null,
  class_name          text,
  total_points        numeric(6,2) not null default 20,
  language            text not null default 'fr',
  exam_type           text not null default 'general',
  subject_images      text[] not null default '{}'::text[],
  subject_validated   boolean not null default false,
  correction_source   jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index if not exists exams_owner_idx on public.exams(owner_id);
create index if not exists exams_class_idx on public.exams(class_name);

-- =============================================================================
-- 3. QUESTIONS (exercices ou questions simples)
-- =============================================================================
create table if not exists public.questions (
  id          uuid primary key default extensions.gen_random_uuid(),
  exam_id     uuid not null references public.exams(id) on delete cascade,
  position    int not null default 0,
  label       text not null,
  statement   text not null default '',
  points      numeric(6,2) not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists questions_exam_idx on public.questions(exam_id);
create index if not exists questions_position_idx on public.questions(exam_id, position);

-- =============================================================================
-- 4. SUB_QUESTIONS (a, b, c… optionnelles)
-- =============================================================================
create table if not exists public.sub_questions (
  id            uuid primary key default extensions.gen_random_uuid(),
  question_id   uuid not null references public.questions(id) on delete cascade,
  position      int not null default 0,
  label         text not null,
  statement     text not null default '',
  points        numeric(6,2) not null default 0,
  created_at    timestamptz not null default now()
);

create index if not exists sub_questions_question_idx on public.sub_questions(question_id);

-- =============================================================================
-- 5. STUDENT_COPIES (copies scannées)
-- =============================================================================
create type public.copy_status as enum ('pending', 'processing', 'graded', 'error');

create table if not exists public.student_copies (
  id              uuid primary key default extensions.gen_random_uuid(),
  exam_id         uuid not null references public.exams(id) on delete cascade,
  student_name    text not null,
  student_ref     text,
  page_images     text[] not null default '{}'::text[],
  status          public.copy_status not null default 'pending',
  general_comment text not null default '',
  confidence      numeric(4,3) not null default 0,
  created_at      timestamptz not null default now(),
  graded_at       timestamptz
);

create index if not exists student_copies_exam_idx on public.student_copies(exam_id);
create index if not exists student_copies_status_idx on public.student_copies(status);

-- =============================================================================
-- 6. QUESTION_GRADES (note par leaf — question simple ou sous-question)
-- =============================================================================
create table if not exists public.question_grades (
  id          uuid primary key default extensions.gen_random_uuid(),
  copy_id     uuid not null references public.student_copies(id) on delete cascade,
  leaf_id     uuid not null,                 -- id de question OU sub_question
  score       numeric(6,2) not null default 0,
  comment     text not null default '',
  created_at  timestamptz not null default now()
);

create index if not exists question_grades_copy_idx on public.question_grades(copy_id);
create unique index if not exists question_grades_unique on public.question_grades(copy_id, leaf_id);

-- =============================================================================
-- 7. Trigger : auto-création du profil à l'inscription
-- =============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'displayName', split_part(new.email, '@', 1))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- =============================================================================
-- 8. Trigger : updated_at automatique
-- =============================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

create trigger exams_set_updated_at
  before update on public.exams
  for each row execute procedure public.set_updated_at();

-- =============================================================================
-- 9. ROW LEVEL SECURITY (chaque prof ne voit que ses données)
-- =============================================================================
alter table public.profiles        enable row level security;
alter table public.exams           enable row level security;
alter table public.questions       enable row level security;
alter table public.sub_questions   enable row level security;
alter table public.student_copies  enable row level security;
alter table public.question_grades enable row level security;

-- ----- profiles -----
create policy "select_own_profile" on public.profiles
  for select using (auth.uid() = id);
create policy "insert_own_profile" on public.profiles
  for insert with check (auth.uid() = id);
create policy "update_own_profile" on public.profiles
  for update using (auth.uid() = id);

-- ----- exams -----
create policy "select_own_exams" on public.exams
  for select using (auth.uid() = owner_id);
create policy "insert_own_exams" on public.exams
  for insert with check (auth.uid() = owner_id);
create policy "update_own_exams" on public.exams
  for update using (auth.uid() = owner_id);
create policy "delete_own_exams" on public.exams
  for delete using (auth.uid() = owner_id);

-- ----- questions / sub_questions / copies / grades : accès via exam owner -----
create policy "manage_questions_via_exam" on public.questions
  for all
  using (
    exists (
      select 1 from public.exams e
      where e.id = questions.exam_id and e.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.exams e
      where e.id = questions.exam_id and e.owner_id = auth.uid()
    )
  );

create policy "manage_sub_questions_via_exam" on public.sub_questions
  for all
  using (
    exists (
      select 1 from public.questions q
      join public.exams e on e.id = q.exam_id
      where q.id = sub_questions.question_id and e.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.questions q
      join public.exams e on e.id = q.exam_id
      where q.id = sub_questions.question_id and e.owner_id = auth.uid()
    )
  );

create policy "manage_copies_via_exam" on public.student_copies
  for all
  using (
    exists (
      select 1 from public.exams e
      where e.id = student_copies.exam_id and e.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.exams e
      where e.id = student_copies.exam_id and e.owner_id = auth.uid()
    )
  );

create policy "manage_grades_via_copy" on public.question_grades
  for all
  using (
    exists (
      select 1 from public.student_copies c
      join public.exams e on e.id = c.exam_id
      where c.id = question_grades.copy_id and e.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.student_copies c
      join public.exams e on e.id = c.exam_id
      where c.id = question_grades.copy_id and e.owner_id = auth.uid()
    )
  );

-- =============================================================================
-- 10. STORAGE : buckets pour images (sujets & copies)
-- =============================================================================
insert into storage.buckets (id, name, public)
values
  ('subjects', 'subjects', false),
  ('copies',   'copies',   false),
  ('avatars',  'avatars',  true)   -- avatars publics
on conflict (id) do nothing;

-- Policies storage (chaque user lit/écrit dans son propre dossier)
create policy "Users manage own subject files" on storage.objects
  for all using (
    bucket_id = 'subjects'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'subjects'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users manage own copy files" on storage.objects
  for all using (
    bucket_id = 'copies'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'copies'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users manage own avatar" on storage.objects
  for all using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Avatars are publicly readable" on storage.objects
  for select using (bucket_id = 'avatars');
