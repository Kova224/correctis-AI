/// Modèles du système de crédits Pay-as-you-go (EduCorrect).
///
/// Grille tarifaire v5 (septembre 2026) — marge minimale, multi-devises :
///   - 1 crédit = 1 copie corrigée par l'IA, jusqu'à 8 pages
///     (au-delà, barème pages → crédits : cf. [CreditRules]).
///   - Deux grilles autonomes XOF et GNF (aucune conversion affichée).
///   - Crédits valables 30 jours après confirmation du paiement.
library;

import 'billing.dart';

/// Catalogue d'un pack (statique côté Flutter, miroir de credit_packs SQL —
/// migration 20261015000001_pricing_grid_v5.sql).
enum CreditPackScope { solo, establishment }

class CreditPack {
  final String code;
  final CreditPackScope scope;
  final String name;
  final int copiesMin;
  final int copiesMax;

  /// Prix du pack en XOF (Bénin, Burkina Faso, Côte d'Ivoire, Mali, Niger,
  /// Sénégal, Togo).
  final int priceXof;

  /// Prix du pack en GNF (Guinée). Arrondi indépendamment du prix XOF.
  final int priceGnf;
  final String? marketingLabel;
  final String? usageHint;

  const CreditPack({
    required this.code,
    required this.scope,
    required this.name,
    required this.copiesMin,
    required this.copiesMax,
    required this.priceXof,
    required this.priceGnf,
    this.marketingLabel,
    this.usageHint,
  });

  bool get isFree => code == 'discovery';
  bool get isQuoteOnly => copiesMax >= 5001;

  /// Prix du pack dans la devise du compte.
  int priceFor(BillingCurrency currency) =>
      currency == BillingCurrency.gnf ? priceGnf : priceXof;

  /// Prix par copie (= par crédit), arrondi à l'unité comme dans la grille.
  int pricePerCopy(BillingCurrency currency) =>
      copiesMax == 0 ? 0 : (priceFor(currency) / copiesMax).round();

  String get rangeLabel =>
      copiesMax == copiesMin ? '$copiesMin copies' : '$copiesMin – $copiesMax copies';

  static const List<CreditPack> soloPacks = [
    CreditPack(
      code: 'discovery',
      scope: CreditPackScope.solo,
      name: 'Découverte',
      copiesMin: 1,
      copiesMax: 3,
      priceXof: 0,
      priceGnf: 0,
      usageHint: '3 copies offertes à vie · 8 pages max chacune',
    ),
    CreditPack(
      code: 'micro',
      scope: CreditPackScope.solo,
      name: 'Micro',
      copiesMin: 4,
      copiesMax: 15,
      priceXof: 450,
      priceGnf: 7000,
      usageHint: '1 classe, petit DS',
    ),
    CreditPack(
      code: 'solo_s',
      scope: CreditPackScope.solo,
      name: 'Solo S',
      copiesMin: 16,
      copiesMax: 30,
      priceXof: 875,
      priceGnf: 13500,
      usageHint: '1 classe, 1 DS',
    ),
    CreditPack(
      code: 'solo_m',
      scope: CreditPackScope.solo,
      name: 'Solo M',
      copiesMin: 31,
      copiesMax: 80,
      priceXof: 2300,
      priceGnf: 35500,
      marketingLabel: 'Populaire',
      usageHint: '2-3 classes, 1 DS',
    ),
    CreditPack(
      code: 'solo_l',
      scope: CreditPackScope.solo,
      name: 'Solo L',
      copiesMin: 81,
      copiesMax: 150,
      priceXof: 4250,
      priceGnf: 65500,
      usageHint: '1 trimestre complet',
    ),
    CreditPack(
      code: 'solo_xl',
      scope: CreditPackScope.solo,
      name: 'Solo XL',
      copiesMin: 151,
      copiesMax: 300,
      priceXof: 8400,
      priceGnf: 130000,
      usageHint: 'Plusieurs niveaux',
    ),
    CreditPack(
      code: 'solo_max',
      scope: CreditPackScope.solo,
      name: 'Solo MAX',
      copiesMin: 301,
      copiesMax: 500,
      priceXof: 14000,
      priceGnf: 216500,
      usageHint: 'Université / Formation',
    ),
  ];

  static const List<CreditPack> establishmentPacks = [
    CreditPack(
      code: 'estab_small',
      scope: CreditPackScope.establishment,
      name: 'Petit',
      copiesMin: 1,
      copiesMax: 200,
      priceXof: 6000,
      priceGnf: 93000,
      usageHint: 'Petit lycée / collège',
    ),
    CreditPack(
      code: 'estab_mid',
      scope: CreditPackScope.establishment,
      name: 'Moyen',
      copiesMin: 201,
      copiesMax: 500,
      priceXof: 14500,
      priceGnf: 227000,
      usageHint: 'Lycée moyen',
    ),
    CreditPack(
      code: 'estab_large',
      scope: CreditPackScope.establishment,
      name: 'Grand lycée',
      copiesMin: 501,
      copiesMax: 1000,
      priceXof: 28500,
      priceGnf: 445000,
      usageHint: 'Grand lycée',
    ),
    CreditPack(
      code: 'estab_uni',
      scope: CreditPackScope.establishment,
      name: 'Université',
      copiesMin: 1001,
      copiesMax: 2500,
      priceXof: 70500,
      priceGnf: 1095000,
      usageHint: 'Université / Réseau',
    ),
    CreditPack(
      code: 'estab_group',
      scope: CreditPackScope.establishment,
      name: 'Groupe',
      copiesMin: 2501,
      copiesMax: 5000,
      priceXof: 140000,
      priceGnf: 2165000,
      usageHint: 'Groupe scolaire',
    ),
    CreditPack(
      code: 'estab_institution',
      scope: CreditPackScope.establishment,
      name: 'Institution',
      copiesMin: 5001,
      copiesMax: 5001,
      priceXof: 0,
      priceGnf: 0,
      usageHint: 'Institution nationale — sur devis',
    ),
  ];

  static CreditPack? byCode(String code) {
    for (final p in [...soloPacks, ...establishmentPacks]) {
      if (p.code == code) return p;
    }
    return null;
  }
}

/// Lot de crédits acheté ou offert (FIFO par expiration).
enum CreditLotSource { purchase, discovery, adminGrant }
enum CreditLotStatus { active, exhausted, expired, revoked }

class CreditLot {
  final String id;
  final String packCode;
  final String packName;
  final CreditLotSource source;
  final int creditsTotal;
  final int creditsRemaining;
  final DateTime purchasedAt;
  final DateTime expiresAt;
  final CreditLotStatus status;

  const CreditLot({
    required this.id,
    required this.packCode,
    required this.packName,
    required this.source,
    required this.creditsTotal,
    required this.creditsRemaining,
    required this.purchasedAt,
    required this.expiresAt,
    required this.status,
  });

  bool get isDiscovery => source == CreditLotSource.discovery;
  bool get isActive => status == CreditLotStatus.active;
  Duration get timeUntilExpiration => expiresAt.difference(DateTime.now());
  int get daysUntilExpiration =>
      timeUntilExpiration.isNegative ? 0 : timeUntilExpiration.inDays;
  bool get isUrgent => daysUntilExpiration <= 3 && creditsRemaining > 0;
  double get progressFraction =>
      creditsTotal == 0 ? 0 : creditsRemaining / creditsTotal;

  factory CreditLot.fromMap(Map<String, dynamic> row) {
    return CreditLot(
      id: row['out_id']?.toString() ?? '',
      packCode: (row['out_pack_code'] ?? '').toString(),
      packName: (row['out_pack_name'] ?? '').toString(),
      source: _sourceFromString(row['out_source']?.toString()),
      creditsTotal: (row['out_credits_total'] as num?)?.toInt() ?? 0,
      creditsRemaining: (row['out_credits_remaining'] as num?)?.toInt() ?? 0,
      purchasedAt: DateTime.tryParse(row['out_purchased_at']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(row['out_expires_at']?.toString() ?? '') ??
          DateTime.now(),
      status: _statusFromString(row['out_status']?.toString()),
    );
  }

  static CreditLotSource _sourceFromString(String? s) {
    switch (s) {
      case 'discovery':
        return CreditLotSource.discovery;
      case 'admin_grant':
        return CreditLotSource.adminGrant;
      case 'purchase':
      default:
        return CreditLotSource.purchase;
    }
  }

  static CreditLotStatus _statusFromString(String? s) {
    switch (s) {
      case 'exhausted':
        return CreditLotStatus.exhausted;
      case 'expired':
        return CreditLotStatus.expired;
      case 'revoked':
        return CreditLotStatus.revoked;
      case 'active':
      default:
        return CreditLotStatus.active;
    }
  }
}

/// Wallet global (synthèse) — total + prochaine expiration.
class CreditWallet {
  final int totalCredits;
  final int activeLotsCount;
  final DateTime? nextExpiration;
  final int? nextExpirationCredits;
  final bool discoveryUsed;

  const CreditWallet({
    required this.totalCredits,
    required this.activeLotsCount,
    this.nextExpiration,
    this.nextExpirationCredits,
    required this.discoveryUsed,
  });

  bool get isEmpty => totalCredits == 0;

  factory CreditWallet.empty() => const CreditWallet(
        totalCredits: 0,
        activeLotsCount: 0,
        discoveryUsed: false,
      );

  factory CreditWallet.fromMap(Map<String, dynamic> row) {
    return CreditWallet(
      totalCredits: (row['out_total_credits'] as num?)?.toInt() ?? 0,
      activeLotsCount: (row['out_active_lots_count'] as num?)?.toInt() ?? 0,
      nextExpiration: row['out_next_expiration'] != null
          ? DateTime.tryParse(row['out_next_expiration'].toString())
          : null,
      nextExpirationCredits:
          (row['out_next_expiration_credits'] as num?)?.toInt(),
      discoveryUsed: row['out_discovery_used'] as bool? ?? false,
    );
  }
}

/// Entrée d'historique (transactions de crédits).
enum CreditTxnType { grant, reserve, consume, refund, expire, revoke }

class CreditTransaction {
  final String id;
  final CreditTxnType type;
  final int delta;
  final String? reason;
  final String? packName;
  final int? paymentAmountGnf;
  final int? paymentAmountFcfa;
  final String? paymentCurrency;
  final String? paymentMethod;
  final String? paymentStatus;
  final DateTime createdAt;

  const CreditTransaction({
    required this.id,
    required this.type,
    required this.delta,
    required this.createdAt,
    this.reason,
    this.packName,
    this.paymentAmountGnf,
    this.paymentAmountFcfa,
    this.paymentCurrency,
    this.paymentMethod,
    this.paymentStatus,
  });

  bool get isPurchase =>
      type == CreditTxnType.grant && reason == 'purchase';
  bool get isDiscovery =>
      type == CreditTxnType.grant && reason == 'discovery';
  bool get isRefund => type == CreditTxnType.refund;
  bool get isConsumption =>
      type == CreditTxnType.consume || type == CreditTxnType.reserve;

  factory CreditTransaction.fromMap(Map<String, dynamic> row) {
    return CreditTransaction(
      id: row['out_id']?.toString() ?? '',
      type: _typeFromString(row['out_txn_type']?.toString()),
      delta: (row['out_delta'] as num?)?.toInt() ?? 0,
      reason: row['out_reason']?.toString(),
      packName: row['out_pack_name']?.toString(),
      paymentAmountGnf: (row['out_payment_amount_gnf'] as num?)?.toInt(),
      paymentAmountFcfa: (row['out_payment_amount_fcfa'] as num?)?.toInt(),
      paymentCurrency: row['out_payment_currency']?.toString(),
      paymentMethod: row['out_payment_method']?.toString(),
      paymentStatus: row['out_payment_status']?.toString(),
      createdAt: DateTime.tryParse(row['out_created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static CreditTxnType _typeFromString(String? s) {
    switch (s) {
      case 'reserve':
        return CreditTxnType.reserve;
      case 'consume':
        return CreditTxnType.consume;
      case 'refund':
        return CreditTxnType.refund;
      case 'expire':
        return CreditTxnType.expire;
      case 'revoke':
        return CreditTxnType.revoke;
      case 'grant':
      default:
        return CreditTxnType.grant;
    }
  }
}

/// Résultat d'une création d'ordre de paiement (avant redirection CinetPay).
/// Montant exprimé dans la devise du compte (XOF ou GNF), sans conversion.
class PaymentOrderDraft {
  final String orderId;
  final int amount;
  final BillingCurrency currency;
  final String countryCode;
  final int copiesCount;
  final String packName;

  const PaymentOrderDraft({
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.countryCode,
    required this.copiesCount,
    required this.packName,
  });
}

/// Résultat d'une réservation de crédits (avant correction IA).
class ReserveCreditResult {
  final bool ok;
  final String? lotId;
  final int? remainingAfter;

  /// 'OK_PERSONAL'|'OK_POOL'|'OK_ALREADY_RESERVED'|'OK_INCLUDED'|
  /// 'NO_CREDITS'|'NO_CREDITS_IN_POOL'|'QUOTA_EXCEEDED'|'QUOTA_NOT_SET'|...
  final String reason;

  /// Crédits débités pour cette copie (selon le nombre de pages).
  final int credits;
  final int pages;

  /// Solde utilisable au moment de la vérification.
  final int available;

  const ReserveCreditResult({
    required this.ok,
    required this.reason,
    this.lotId,
    this.remainingAfter,
    this.credits = 0,
    this.pages = 0,
    this.available = 0,
  });

  factory ReserveCreditResult.fromMap(Map<String, dynamic> row) {
    return ReserveCreditResult(
      ok: row['out_ok'] as bool? ?? false,
      lotId: row['out_lot_id']?.toString(),
      remainingAfter: (row['out_remaining_after'] as num?)?.toInt(),
      reason: (row['out_reason'] ?? 'NO_CREDITS').toString(),
      credits: (row['out_credits'] as num?)?.toInt() ?? 0,
      pages: (row['out_pages'] as num?)?.toInt() ?? 0,
      available: (row['out_available'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Quota d'un prof dans une école.
class TeacherQuota {
  final String userId;
  final String displayName;
  final String? matiere;
  final int limitTotal; // 0 = pas de quota
  final int used;
  final bool blocked;

  const TeacherQuota({
    required this.userId,
    required this.displayName,
    required this.limitTotal,
    required this.used,
    required this.blocked,
    this.matiere,
  });

  bool get hasLimit => limitTotal > 0;
  int get remaining => hasLimit ? (limitTotal - used).clamp(0, limitTotal) : 0;
  double get progressFraction =>
      hasLimit ? (used / limitTotal).clamp(0, 1).toDouble() : 0;

  factory TeacherQuota.fromMap(Map<String, dynamic> row) {
    return TeacherQuota(
      userId: row['out_user_id']?.toString() ?? '',
      displayName:
          (row['out_display_name'] ?? 'Enseignant').toString(),
      matiere: row['out_matiere']?.toString(),
      limitTotal: (row['out_limit_total'] as num?)?.toInt() ?? 0,
      used: (row['out_used'] as num?)?.toInt() ?? 0,
      blocked: row['out_blocked'] as bool? ?? false,
    );
  }
}

/// Wallet établissement.
class OrgCreditWallet {
  /// Crédits physiques restants dans les lots (achetés - consommés).
  final int totalCredits;
  final int activeLotsCount;
  final DateTime? nextExpiration;
  final String? activePackName;
  final int? activePackTotal;

  /// Michel : crédits déjà attribués aux quotas profs (non consommés).
  final int engagedCredits;

  /// Pool réellement dispo pour de nouvelles attributions
  /// = totalCredits - engagedCredits.
  final int availableCredits;

  const OrgCreditWallet({
    required this.totalCredits,
    required this.activeLotsCount,
    this.nextExpiration,
    this.activePackName,
    this.activePackTotal,
    this.engagedCredits = 0,
    this.availableCredits = 0,
  });

  bool get isEmpty => totalCredits == 0;

  double get progressFraction {
    if (activePackTotal == null || activePackTotal! <= 0) return 0;
    return (totalCredits / activePackTotal!).clamp(0, 1).toDouble();
  }

  factory OrgCreditWallet.empty() => const OrgCreditWallet(
        totalCredits: 0,
        activeLotsCount: 0,
      );

  factory OrgCreditWallet.fromMap(Map<String, dynamic> row) {
    final total = (row['out_total_credits'] as num?)?.toInt() ?? 0;
    final engaged = (row['out_engaged_credits'] as num?)?.toInt() ?? 0;
    return OrgCreditWallet(
      totalCredits: total,
      activeLotsCount: (row['out_active_lots_count'] as num?)?.toInt() ?? 0,
      nextExpiration: row['out_next_expiration'] != null
          ? DateTime.tryParse(row['out_next_expiration'].toString())
          : null,
      activePackName: row['out_active_pack_name']?.toString(),
      activePackTotal: (row['out_active_pack_total'] as num?)?.toInt(),
      engagedCredits: engaged,
      availableCredits: (row['out_available_credits'] as num?)?.toInt() ??
          (total - engaged).clamp(0, total),
    );
  }
}

/// Quota individuel du prof courant (attribué par l'admin de son école).
class MyTeacherQuota {
  final String establishmentId;
  final String establishmentName;
  final int limitTotal;
  final int used;
  final int remaining;
  final bool hasLimit;

  const MyTeacherQuota({
    required this.establishmentId,
    required this.establishmentName,
    required this.limitTotal,
    required this.used,
    required this.remaining,
    required this.hasLimit,
  });

  double get progressFraction {
    if (limitTotal <= 0) return 0;
    return (used / limitTotal).clamp(0, 1).toDouble();
  }

  factory MyTeacherQuota.fromMap(Map<String, dynamic> row) {
    return MyTeacherQuota(
      establishmentId: (row['out_establishment_id'] ?? '').toString(),
      establishmentName: (row['out_establishment_name'] ?? '').toString(),
      limitTotal: (row['out_limit_total'] as num?)?.toInt() ?? 0,
      used: (row['out_used'] as num?)?.toInt() ?? 0,
      remaining: (row['out_remaining'] as num?)?.toInt() ?? 0,
      hasLimit: row['out_has_limit'] as bool? ?? false,
    );
  }
}
