import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/locale_service.dart';

/// Catalogue de traductions multilingues (FR / EN / AR).
///
/// Utilisation dans les écrans :
/// ```dart
/// Text(S.of(context).greetingHello)
/// // ou via extension :
/// Text('greeting_hello'.tr(context))
/// ```
///
/// Chaque méthode renvoie la chaîne dans la langue courante.
class S {
  final Locale locale;
  const S(this.locale);

  static S of(BuildContext context) {
    final svc = context.watch<LocaleService>();
    return S(svc.locale);
  }

  /// Version qui ne souscrit pas (pour usage dans onPressed etc.)
  static S read(BuildContext context) {
    final svc = context.read<LocaleService>();
    return S(svc.locale);
  }

  /// Helper public pour piocher la bonne chaîne selon la langue.
  /// Utile pour des chaînes ponctuelles qui ne méritent pas leur propre clé.
  String pick(String fr, String en, String ar) {
    switch (locale.languageCode) {
      case 'en':
        return en;
      case 'ar':
        return ar;
      case 'fr':
      default:
        return fr;
    }
  }

  String _pick(String fr, String en, String ar) => pick(fr, en, ar);

  // ─────────────────────────── COMMUN ───────────────────────────
  String get appName => 'Correctis';

  String get cancel => _pick('Annuler', 'Cancel', 'إلغاء');
  String get confirm => _pick('Confirmer', 'Confirm', 'تأكيد');
  String get save => _pick('Enregistrer', 'Save', 'حفظ');
  String get delete => _pick('Supprimer', 'Delete', 'حذف');
  String get edit => _pick('Modifier', 'Edit', 'تعديل');
  String get close => _pick('Fermer', 'Close', 'إغلاق');
  String get retry => _pick('Réessayer', 'Retry', 'إعادة المحاولة');
  String get loading => _pick('Chargement…', 'Loading…', 'جارٍ التحميل…');
  String get search => _pick('Rechercher', 'Search', 'بحث');
  String get all => _pick('Tous', 'All', 'الكل');
  String get none => _pick('Aucun', 'None', 'لا شيء');
  String get yes => _pick('Oui', 'Yes', 'نعم');
  String get no => _pick('Non', 'No', 'لا');
  String get send => _pick('Envoyer', 'Send', 'إرسال');

  // ─────────────────────────── HOME ───────────────────────────
  String get hello => _pick('BONJOUR', 'HELLO', 'مرحبا');
  String get teacher => _pick('Professeur', 'Teacher', 'الأستاذ');
  String get schoolNotSet =>
      _pick('Lycée non renseigné', 'School not set', 'المدرسة غير محددة');
  String get freeTrialBadge => _pick(
        'Découverte · 3 copies offertes',
        'Discovery · 3 free copies',
        'اكتشاف · 3 نسخ مجانية',
      );
  String get myRecentExams => _pick(
        'MES EXAMENS RÉCENTS',
        'MY RECENT EXAMS',
        'امتحاناتي الأخيرة',
      );
  String get noExams => _pick('Aucun examen', 'No exam', 'لا توجد امتحانات');
  String get createFirstExam => _pick(
        'Créez votre premier examen pour\ncommencer à corriger des copies.',
        'Create your first exam to start\ngrading papers.',
        'أنشئ امتحانك الأول لبدء\nتصحيح الأوراق.',
      );
  String get createExam =>
      _pick('+ CRÉER UN EXAMEN', '+ CREATE AN EXAM', '+ إنشاء امتحان');
  String get searchExam => _pick(
        'Rechercher un examen ou une classe…',
        'Search an exam or class…',
        'ابحث عن امتحان أو قسم…',
      );
  String get noExamMatching => _pick(
        'Aucun examen correspondant',
        'No matching exam',
        'لا يوجد امتحان مطابق',
      );

  String exams(int n) =>
      _pick('$n examen${n != 1 ? "s" : ""}', '$n exam${n != 1 ? "s" : ""}',
          '$n امتحان');

  // ─────────────────── BOTTOM NAV PROF ───────────────────
  String get tabHome => _pick('Accueil', 'Home', 'الرئيسية');
  String get tabExams => _pick('Examens', 'Exams', 'الامتحانات');
  String get tabScanner => _pick('Scanner', 'Scanner', 'مسح');
  String get tabResults => _pick('Résultats', 'Results', 'النتائج');
  String get tabProfile => _pick('Profil', 'Profile', 'الملف');

  // ─────────────────── BOTTOM NAV ADMIN ───────────────────
  String get tabDashboard =>
      _pick('Tableau', 'Dashboard', 'لوحة القيادة');
  String get tabTeachers => _pick('Profs', 'Teachers', 'الأساتذة');
  String get tabCasier => _pick('Casier', 'Casebook', 'السجل');
  String get tabAnalytics => _pick('Analytique', 'Analytics', 'التحليلات');

  // ─────────────────── COPIES / RECHERCHE ───────────────────
  String get searchCopy => _pick(
        'Rechercher (prénom, nom, matricule)…',
        'Search (first name, last name, ID)…',
        'بحث (الاسم، اللقب، الرقم)…',
      );
  String get copiesToReview => _pick(
        'COPIES À REPRENDRE',
        'COPIES TO REVIEW',
        'الأوراق المراد إعادتها',
      );
  String copiesToReviewDesc(int n) => _pick(
        '$n copie${n != 1 ? "s" : ""} nécessite${n != 1 ? "nt" : ""} votre attention',
        '$n cop${n != 1 ? "ies" : "y"} need${n != 1 ? "" : "s"} your attention',
        '$n ورقة تتطلب انتباهك',
      );
  String get reviewReasonOffTopic => _pick(
        'Hors-sujet détecté',
        'Off-topic detected',
        'خارج عن الموضوع',
      );
  String get reviewReasonIllegible => _pick(
        'Zones illisibles',
        'Illegible areas',
        'مناطق غير مقروءة',
      );

  // ─────────────────── PROFIL / PARAMÈTRES ───────────────────
  String get editProfile =>
      _pick('Modifier mon profil', 'Edit profile', 'تعديل ملفي');
  String get changePassword =>
      _pick('Changer le mot de passe', 'Change password', 'تغيير كلمة المرور');
  String get language => _pick('Langue', 'Language', 'اللغة');
  String get notifications =>
      _pick('Notifications', 'Notifications', 'الإشعارات');
  String get support =>
      _pick('Support / Aide', 'Support / Help', 'الدعم / المساعدة');
  String get logout => _pick('Déconnexion', 'Log out', 'تسجيل الخروج');
  String get subscription =>
      _pick('Mes crédits', 'My credits', 'رصيدي');
  String get schoolView => _pick('Vue École', 'School view', 'عرض المدرسة');

  // ─────────────────── SUPPORT ───────────────────
  String get supportTitle =>
      _pick('Contacter le support', 'Contact support', 'الاتصال بالدعم');
  String get supportSubtitle => _pick(
        'Notre équipe répond sous 24 h. Choisissez le canal qui vous convient.',
        'Our team responds within 24 hours. Pick the channel you prefer.',
        'يستجيب فريقنا في غضون 24 ساعة. اختر القناة المناسبة.',
      );
  String get supportEmail => _pick('Par email', 'By email', 'بالبريد الإلكتروني');
  String get supportWhatsapp => _pick('Sur WhatsApp', 'On WhatsApp', 'عبر واتساب');
  String get supportForm => _pick(
        'Envoyer un message',
        'Send a message',
        'إرسال رسالة',
      );
  String get supportFormHint => _pick(
        'Décrivez votre problème ou votre question…',
        'Describe your issue or question…',
        'صف مشكلتك أو سؤالك…',
      );
  String get supportSent => _pick(
        'Message envoyé. Merci !',
        'Message sent. Thank you!',
        'تم إرسال الرسالة. شكراً!',
      );
  String get supportEmailLabel => 'support@correctis.app';
  String get supportWhatsappLabel => '+216 55 555 555';
}

/// Extension pour accès rapide aux chaînes : `S.of(context).xyz`.
/// Pas d'helper `String.tr` pour rester strict-typé (autocomplete + erreurs
/// de compile si on tape un nom de clé inexistant).
