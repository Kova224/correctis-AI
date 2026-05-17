/// Configuration Supabase.
///
/// IMPORTANT : la clé `anonKey` est **publique par design** chez Supabase
/// (embarquée dans toutes les apps client). La sécurité est garantie par
/// **Row Level Security** (RLS) sur la base de données : chaque utilisateur
/// n'accède qu'à ses propres données.
///
/// La clé SECRÈTE est la `service_role` key — celle-là ne doit JAMAIS être
/// dans l'app mobile ni sur GitHub. Elle ne sert qu'aux backends de confiance.
class SupabaseConfig {
  static const String url = 'https://nqwymypfykiengbqdqim.supabase.co';

  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5xd3lteXBmeWtpZW5nYnFkcWltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwMjcwNjQsImV4cCI6MjA5NDYwMzA2NH0.0nwgtasTBKARPmS4N4pHb6CusfiwVlqXoxb98ZqvTmk';

  // Noms des buckets de stockage (alignés avec la migration SQL)
  static const String subjectsBucket = 'subjects';
  static const String copiesBucket = 'copies';
  static const String avatarsBucket = 'avatars';
}
