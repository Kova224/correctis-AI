import '../services/locale_service.dart';

/// Système de traductions léger sans dépendance flutter_localizations.
///
/// Utilisation :
///   final t = AppStrings.of(context);   // (avec extension Provider)
///   Text(t.profile)
///
/// Pour ajouter une chaîne : ajoutez la clé dans chaque map ci-dessous.
class AppStrings {
  final AppLanguage lang;
  const AppStrings(this.lang);

  String _t(Map<AppLanguage, String> map) =>
      map[lang] ?? map[AppLanguage.french] ?? '';

  // ─── Navigation / Tabs ─────────────────────────────────────────────────
  String get home => _t(const {
        AppLanguage.french: 'Accueil',
        AppLanguage.english: 'Home',
        AppLanguage.arabic: 'الرئيسية',
      });

  String get exams => _t(const {
        AppLanguage.french: 'Examens',
        AppLanguage.english: 'Exams',
        AppLanguage.arabic: 'الامتحانات',
      });

  String get profile => _t(const {
        AppLanguage.french: 'Profil',
        AppLanguage.english: 'Profile',
        AppLanguage.arabic: 'الملف الشخصي',
      });

  String get settings => _t(const {
        AppLanguage.french: 'Paramètres',
        AppLanguage.english: 'Settings',
        AppLanguage.arabic: 'الإعدادات',
      });

  // ─── Profil ───────────────────────────────────────────────────────────
  String get language => _t(const {
        AppLanguage.french: 'Langue',
        AppLanguage.english: 'Language',
        AppLanguage.arabic: 'اللغة',
      });

  String get notifications => _t(const {
        AppLanguage.french: 'Notifications',
        AppLanguage.english: 'Notifications',
        AppLanguage.arabic: 'الإشعارات',
      });

  String get editProfile => _t(const {
        AppLanguage.french: 'Modifier le profil',
        AppLanguage.english: 'Edit profile',
        AppLanguage.arabic: 'تعديل الملف الشخصي',
      });

  String get changePassword => _t(const {
        AppLanguage.french: 'Changer le mot de passe',
        AppLanguage.english: 'Change password',
        AppLanguage.arabic: 'تغيير كلمة المرور',
      });

  String get logout => _t(const {
        AppLanguage.french: 'Se déconnecter',
        AppLanguage.english: 'Sign out',
        AppLanguage.arabic: 'تسجيل الخروج',
      });

  // ─── Notifications préférences ────────────────────────────────────────
  String get notifyCopiesReady => _t(const {
        AppLanguage.french: 'Copies corrigées',
        AppLanguage.english: 'Graded copies',
        AppLanguage.arabic: 'الأوراق المصححة',
      });

  String get notifyCopiesReadyDesc => _t(const {
        AppLanguage.french: 'Recevoir une notification quand une correction est prête',
        AppLanguage.english: 'Get notified when a correction is ready',
        AppLanguage.arabic: 'إشعار عند جاهزية التصحيح',
      });

  String get notifyInvitations => _t(const {
        AppLanguage.french: 'Invitations',
        AppLanguage.english: 'Invitations',
        AppLanguage.arabic: 'الدعوات',
      });

  String get notifyInvitationsDesc => _t(const {
        AppLanguage.french: 'Rappels pour les invitations en attente',
        AppLanguage.english: 'Reminders for pending invitations',
        AppLanguage.arabic: 'تذكير بالدعوات المعلقة',
      });

  String get notifyQuota => _t(const {
        AppLanguage.french: 'Crédits faibles',
        AppLanguage.english: 'Low credits',
        AppLanguage.arabic: 'رصيد منخفض',
      });

  String get notifyQuotaDesc => _t(const {
        AppLanguage.french: 'Alerte quand il reste 3 crédits ou moins',
        AppLanguage.english: 'Alert when 3 credits or fewer remain',
        AppLanguage.arabic: 'تنبيه عند بقاء 3 أرصدة أو أقل',
      });

  // ─── Generic actions ──────────────────────────────────────────────────
  String get save => _t(const {
        AppLanguage.french: 'Enregistrer',
        AppLanguage.english: 'Save',
        AppLanguage.arabic: 'حفظ',
      });

  String get cancel => _t(const {
        AppLanguage.french: 'Annuler',
        AppLanguage.english: 'Cancel',
        AppLanguage.arabic: 'إلغاء',
      });

  String get retry => _t(const {
        AppLanguage.french: 'Réessayer',
        AppLanguage.english: 'Retry',
        AppLanguage.arabic: 'إعادة المحاولة',
      });

  String get loading => _t(const {
        AppLanguage.french: 'Chargement…',
        AppLanguage.english: 'Loading…',
        AppLanguage.arabic: 'جار التحميل…',
      });

  // ─── Crédits (pay-as-you-go, sans abonnement) ─────────────────────────
  String get credits => _t(const {
        AppLanguage.french: 'Mes crédits',
        AppLanguage.english: 'My credits',
        AppLanguage.arabic: 'رصيدي',
      });

  // ─── App ──────────────────────────────────────────────────────────────
  String get appName => 'Correctis';
}
