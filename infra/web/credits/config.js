// Configuration publique de la page d'achat (mêmes valeurs que l'app :
// lib/config/supabase_config.dart). La clé « anon » est publique par
// conception ; la sécurité repose sur les règles RLS et les RPC du serveur.
window.CORRECTIS_CONFIG = {
  supabaseUrl: 'https://nqwymypfykiengbqdqim.supabase.co',
  supabaseAnonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5xd3lteXBmeWtpZW5nYnFkcWltIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwMjcwNjQsImV4cCI6MjA5NDYwMzA2NH0.0nwgtasTBKARPmS4N4pHb6CusfiwVlqXoxb98ZqvTmk',
  supportEmail: 'support@correctis.app',
  // Paiement par carte (Visa/Mastercard). À passer à true seulement quand
  // CinetPay a activé l'option carte sur le compte marchand ET que le secret
  // Supabase CINETPAY_CARD_ENABLED vaut 1.
  cardEnabled: false,
};
