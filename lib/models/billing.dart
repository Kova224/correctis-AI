/// Facturation multi-devises — grille EduCorrect v5 (septembre 2026).
///
/// - Deux grilles autonomes : XOF (7 pays) et GNF (Guinée). Aucun montant
///   n'est jamais converti ni affiché dans l'autre devise.
/// - Un compte est rattaché à un seul pays de facturation → une seule devise.
/// - 1 crédit = 1 copie corrigée jusqu'à 8 pages (barème [CreditRules]).
library;

/// Devise d'un compte.
enum BillingCurrency {
  xof('XOF', 'FCFA'),
  gnf('GNF', 'GNF');

  /// Code ISO envoyé à CinetPay / stocké en base.
  final String code;

  /// Libellé affiché à côté des montants.
  final String label;

  const BillingCurrency(this.code, this.label);

  static BillingCurrency? fromCode(String? code) {
    switch ((code ?? '').toUpperCase()) {
      case 'XOF':
        return BillingCurrency.xof;
      case 'GNF':
        return BillingCurrency.gnf;
      default:
        return null;
    }
  }

  /// Montant formaté avec séparateur de milliers : « 13 500 GNF ».
  String format(int amount) => '${formatThousands(amount)} $label';
}

/// Pays couverts par CinetPay en Afrique de l'Ouest.
///
/// Hors couverture (autre prestataire requis) : Ghana, Nigeria, Sierra Leone,
/// Liberia, Gambie, Cap-Vert.
enum BillingCountry {
  bj('BJ', 'Bénin', '🇧🇯', '229', BillingCurrency.xof, ['MTN', 'MOOV'], 8, 10),
  bf('BF', 'Burkina Faso', '🇧🇫', '226', BillingCurrency.xof,
      ['OM', 'MOOV', 'WAVE'], 8, 8),
  ci('CI', 'Côte d\'Ivoire', '🇨🇮', '225', BillingCurrency.xof,
      ['OM', 'MTN', 'MOOV', 'WAVE'], 10, 10),
  gn('GN', 'Guinée', '🇬🇳', '224', BillingCurrency.gnf, ['OM', 'MTN'], 8, 9),
  ml('ML', 'Mali', '🇲🇱', '223', BillingCurrency.xof, ['OM', 'MOOV'], 8, 8),
  ne('NE', 'Niger', '🇳🇪', '227', BillingCurrency.xof, ['AIRTEL', 'MOOV'], 8, 8),
  sn('SN', 'Sénégal', '🇸🇳', '221', BillingCurrency.xof,
      ['OM', 'WAVE', 'FREE'], 9, 9),
  tg('TG', 'Togo', '🇹🇬', '228', BillingCurrency.xof, ['MOOV', 'TMONEY'], 8, 8);

  final String code;
  /// Nom affiché du pays (« Côte d'Ivoire »).
  final String displayName;
  final String flag;

  /// Indicatif téléphonique (sans le +).
  final String dialCode;
  final BillingCurrency currency;

  /// Opérateurs Mobile Money proposés (codes courts CinetPay de l'app),
  /// d'après le tableau « Codes pays supportés » de supabase/DEPLOY_CINETPAY.md.
  /// ⚠️ Synchronisé avec OPERATORS_BY_COUNTRY dans
  /// supabase/functions/cinetpay-init-payment/index.ts.
  final List<String> mobileOperators;

  /// Longueur du numéro mobile local (sans indicatif).
  final int phoneMinDigits;
  final int phoneMaxDigits;

  const BillingCountry(
    this.code,
    this.displayName,
    this.flag,
    this.dialCode,
    this.currency,
    this.mobileOperators,
    this.phoneMinDigits,
    this.phoneMaxDigits,
  );

  /// Carte bancaire (Visa/Mastercard) : disponible en XOF, pas encore en GNF.
  bool get cardAvailable => currency == BillingCurrency.xof;

  static BillingCountry? fromCode(String? code) {
    final c = (code ?? '').toUpperCase();
    for (final v in BillingCountry.values) {
      if (v.code == c) return v;
    }
    return null;
  }

  /// Devine le pays depuis un numéro au format international (+224…, 00225…).
  static BillingCountry? guessFromPhone(String? phone) {
    var digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    for (final v in BillingCountry.values) {
      if (digits.startsWith(v.dialCode) &&
          digits.length >= v.dialCode.length + v.phoneMinDigits) {
        return v;
      }
    }
    return null;
  }
}

/// Règles de consommation des crédits (identiques en XOF et en GNF).
class CreditRules {
  CreditRules._();

  /// Nombre max de pages couvertes par 1 crédit.
  static const int pagesPerCredit = 8;

  /// Barème pages → crédits du PDF v5 :
  ///   1–8 → 1 · 9–17 → 2 · 18–25 → 3 · 26–34 → 4 · puis +1 / ≈ 8-9 pages.
  /// Formule exacte : ceil(2 × pages / 17). Miroir de la fonction SQL
  /// `public.credits_for_pages` (le serveur reste la source de vérité).
  static int creditsForPages(int pages) {
    if (pages <= 0) return 0;
    return (2 * pages + 16) ~/ 17;
  }

  static String creditsLabel(int credits) =>
      '$credits crédit${credits > 1 ? 's' : ''}';
}

/// 13500 → « 13 500 ».
String formatThousands(int v) {
  final neg = v < 0;
  final s = v.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return neg ? '-$buf' : buf.toString();
}
