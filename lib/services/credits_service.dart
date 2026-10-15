import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/billing.dart';
import '../models/credits.dart';

/// Service de gestion des crédits Pay-as-you-go (EduCorrect).
///
/// Sépare strictement :
///   - le wallet utilisateur (cette classe via RPCs Supabase)
///   - le solde réel des APIs (Anthropic + Google Cloud, géré hors-app)
///
/// Toutes les opérations passent par RPCs SECURITY DEFINER pour bypasser
/// les RLS récursives (cf. doc Pay-as-you-go, section 5).
class CreditsService extends ChangeNotifier {
  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  // ─── État interne ────────────────────────────────────────────────────────
  CreditWallet _wallet = CreditWallet.empty();
  OrgCreditWallet _orgWallet = OrgCreditWallet.empty();
  List<CreditLot> _lots = const [];
  List<CreditTransaction> _history = const [];
  List<TeacherQuota> _teacherQuotas = const [];
  MyTeacherQuota? _myTeacherQuota;
  List<MyTeacherQuota> _myTeacherQuotasAllSchools = const [];

  bool _loadingWallet = false;
  bool _loadingHistory = false;

  // Grille v5 : pays de facturation du compte (→ devise XOF ou GNF).
  BillingCountry? _billingCountry;
  bool _billingCanChange = true;
  bool _billingLoaded = false;

  /// Appelé quand le solde personnel passe sous le seuil d'alerte
  /// (branché sur NotificationService.notifyQuotaAlmostReached au démarrage).
  Future<void> Function(int remaining)? onLowCredits;
  static const int lowCreditsThreshold = 3;

  // ─── Getters ─────────────────────────────────────────────────────────────
  CreditWallet get wallet => _wallet;
  OrgCreditWallet get orgWallet => _orgWallet;
  List<CreditLot> get lots => _lots;
  List<CreditTransaction> get history => _history;
  List<TeacherQuota> get teacherQuotas => _teacherQuotas;
  MyTeacherQuota? get myTeacherQuota => _myTeacherQuota;
  /// Michel (spec §6) : quota du prof dans CHAQUE école où il est rattaché,
  /// pour l'affichage groupé "Mes examens" (une section par école + solde).
  List<MyTeacherQuota> get myTeacherQuotasAllSchools =>
      _myTeacherQuotasAllSchools;
  bool get loadingWallet => _loadingWallet;
  bool get loadingHistory => _loadingHistory;

  /// Pays de facturation du compte (null tant que non choisi).
  BillingCountry? get billingCountry => _billingCountry;

  /// Devise du compte (null tant que le pays n'est pas choisi).
  BillingCurrency? get billingCurrency => _billingCountry?.currency;

  /// false dès qu'un paiement a été confirmé : la devise est alors verrouillée.
  bool get billingCanChange => _billingCanChange;
  bool get billingLoaded => _billingLoaded;

  int get totalCredits => _wallet.totalCredits;
  bool get hasCredits => _wallet.totalCredits > 0 || _orgWallet.totalCredits > 0;

  /// Capacité totale de correction (perso + pool établissement si membre).
  int get availableCredits => _wallet.totalCredits + _orgWallet.totalCredits;

  // ─── Bootstrap & rafraîchissement ────────────────────────────────────────
  Future<void> bootstrap() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _wallet = CreditWallet.empty();
      _orgWallet = OrgCreditWallet.empty();
      _lots = const [];
      _history = const [];
      _teacherQuotas = const [];
      _billingCountry = null;
      _billingCanChange = true;
      _billingLoaded = false;
      notifyListeners();
      return;
    }
    await Future.wait([
      refreshBilling(),
      refreshWallet(),
      refreshLots(),
      refreshHistory(),
      refreshMyTeacherQuotasAllSchools(),
    ]);
  }

  // ─── Pays de facturation / devise (grille v5) ────────────────────────────

  Future<void> refreshBilling() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _client.rpc('get_my_billing');
      final rows = (res as List?) ?? const <dynamic>[];
      if (rows.isNotEmpty) {
        final row = rows.first as Map<String, dynamic>;
        _billingCountry =
            BillingCountry.fromCode(row['out_country']?.toString());
        _billingCanChange = row['out_can_change'] as bool? ?? true;
      } else {
        _billingCountry = null;
        _billingCanChange = true;
      }
    } catch (e) {
      debugPrint('[CreditsService.refreshBilling] erreur : $e');
    }
    _billingLoaded = true;
    notifyListeners();
  }

  /// Rattache le compte à un pays (donc à une devise). Lance une erreur si
  /// la devise est déjà verrouillée par un paiement confirmé.
  Future<void> setBillingCountry(BillingCountry country) async {
    try {
      await _client.rpc(
        'set_my_billing_country',
        params: {'p_country': country.code},
      );
    } on sb.PostgrestException catch (e) {
      if (e.message.contains('BILLING_COUNTRY_LOCKED')) {
        throw 'La devise de votre compte est verrouillée après le premier '
            'paiement. Contactez le support pour la modifier.';
      }
      rethrow;
    }
    _billingCountry = country;
    _billingLoaded = true;
    notifyListeners();
  }

  /// Charge le quota du prof dans chaque école où il est rattaché.
  Future<void> refreshMyTeacherQuotasAllSchools() async {
    try {
      final res = await _client.rpc('get_my_teacher_quotas');
      final rows = (res as List?) ?? const <dynamic>[];
      _myTeacherQuotasAllSchools = rows
          .map<MyTeacherQuota>(
              (r) => MyTeacherQuota.fromMap(r as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint(
          '[CreditsService.refreshMyTeacherQuotasAllSchools] erreur : $e');
      _myTeacherQuotasAllSchools = const [];
      notifyListeners();
    }
  }

  Future<void> refreshWallet() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    _loadingWallet = true;
    final previousTotal = _wallet.totalCredits;
    notifyListeners();
    try {
      final res = await _client.rpc('get_my_credit_wallet');
      final rows = (res as List?) ?? const <dynamic>[];
      if (rows.isEmpty) {
        _wallet = CreditWallet.empty();
      } else {
        _wallet = CreditWallet.fromMap(rows.first as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[CreditsService.refreshWallet] erreur : $e');
      _wallet = CreditWallet.empty();
    }

    // Pool établissement si admin/prof rattaché
    try {
      final orgRes = await _client.rpc('get_org_credit_wallet');
      final orgRows = (orgRes as List?) ?? const <dynamic>[];
      if (orgRows.isEmpty) {
        _orgWallet = OrgCreditWallet.empty();
      } else {
        _orgWallet =
            OrgCreditWallet.fromMap(orgRows.first as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[CreditsService.refreshOrgWallet] erreur : $e');
      _orgWallet = OrgCreditWallet.empty();
    }

    // B4 (Sprint 4) : charge le quota individuel attribué par l'admin
    try {
      final quotaRes = await _client.rpc('get_my_teacher_quota');
      final quotaRows = (quotaRes as List?) ?? const <dynamic>[];
      if (quotaRows.isEmpty) {
        _myTeacherQuota = null;
      } else {
        _myTeacherQuota =
            MyTeacherQuota.fromMap(quotaRows.first as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('[CreditsService.myTeacherQuota] erreur : $e');
      _myTeacherQuota = null;
    }

    _loadingWallet = false;
    notifyListeners();

    // Alerte « crédits faibles » : uniquement au franchissement du seuil.
    final now = _wallet.totalCredits;
    if (previousTotal > lowCreditsThreshold &&
        now > 0 &&
        now <= lowCreditsThreshold) {
      try {
        await onLowCredits?.call(now);
      } catch (e) {
        debugPrint('[CreditsService.onLowCredits] $e');
      }
    }
  }

  Future<void> refreshLots() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      final res = await _client.rpc('get_my_credit_lots');
      final rows = (res as List?) ?? const <dynamic>[];
      _lots = rows
          .map<CreditLot>(
              (r) => CreditLot.fromMap(r as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[CreditsService.refreshLots] erreur : $e');
      _lots = const [];
      notifyListeners();
    }
  }

  Future<void> refreshHistory({int limit = 30}) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    _loadingHistory = true;
    notifyListeners();
    try {
      final res = await _client.rpc(
        'get_my_credit_history',
        params: {'p_limit': limit},
      );
      final rows = (res as List?) ?? const <dynamic>[];
      _history = rows
          .map<CreditTransaction>(
              (r) => CreditTransaction.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[CreditsService.refreshHistory] erreur : $e');
      _history = const [];
    }
    _loadingHistory = false;
    notifyListeners();
  }

  Future<void> refreshTeacherQuotas() async {
    try {
      final res = await _client.rpc('get_org_teacher_quotas');
      final rows = (res as List?) ?? const <dynamic>[];
      _teacherQuotas = rows
          .map<TeacherQuota>(
              (r) => TeacherQuota.fromMap(r as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[CreditsService.refreshTeacherQuotas] erreur : $e');
      _teacherQuotas = const [];
      notifyListeners();
    }
  }

  // ─── Découverte (3 crédits gratuits à vie) ───────────────────────────────

  /// Tente d'attribuer le pack Découverte si pas déjà fait.
  /// Retourne true si attribué, false si déjà utilisé.
  Future<bool> claimDiscoveryIfEligible() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    try {
      final res = await _client.rpc('grant_discovery_credits');
      final rows = (res as List?) ?? const <dynamic>[];
      if (rows.isEmpty) return false;
      final row = rows.first as Map<String, dynamic>;
      final alreadyUsed = row['out_already_used'] as bool? ?? true;
      if (!alreadyUsed) {
        await Future.wait([refreshWallet(), refreshLots(), refreshHistory()]);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[CreditsService.claimDiscovery] erreur : $e');
      return false;
    }
  }

  // ─── Réservation / consommation / remboursement de crédit ────────────────

  /// Réserve les crédits d'une copie (selon son nombre de pages, FIFO
  /// multi-lots) avant correction. Retourne le résultat (ok, raison, crédits).
  Future<ReserveCreditResult> reserveCredit(
    String copyId, {
    String? establishmentId,
    bool hitl = false,
  }) async {
    try {
      final res = await _client.rpc(
        'reserve_credits',
        params: {
          'p_copy_id': copyId,
          if (establishmentId != null) 'p_establishment_id': establishmentId,
          'p_hitl': hitl,
        },
      );
      final rows = (res as List?) ?? const <dynamic>[];
      if (rows.isEmpty) {
        return const ReserveCreditResult(ok: false, reason: 'NO_RESPONSE');
      }
      final result =
          ReserveCreditResult.fromMap(rows.first as Map<String, dynamic>);
      // Met à jour le wallet local immédiatement (UI réactive)
      if (result.ok) await refreshWallet();
      return result;
    } catch (e) {
      debugPrint('[CreditsService.reserveCredit] erreur : $e');
      return ReserveCreditResult(ok: false, reason: 'ERROR: $e');
    }
  }

  /// Confirme la consommation après correction réussie.
  Future<void> consumeCredit(String copyId) async {
    try {
      await _client.rpc('consume_credit', params: {'p_copy_id': copyId});
    } catch (e) {
      debugPrint('[CreditsService.consumeCredit] erreur : $e');
    }
  }

  /// Rembourse les crédits réservés si la correction a échoué
  /// (idempotent : un double appel ne rembourse qu'une fois).
  Future<bool> refundCredit(String copyId, {String reason = 'api_error'}) async {
    try {
      final res = await _client.rpc(
        'refund_credits',
        params: {'p_copy_id': copyId, 'p_reason': reason},
      );
      await refreshWallet();
      return ((res as num?) ?? 0) > 0;
    } catch (e) {
      debugPrint('[CreditsService.refundCredit] erreur : $e');
      return false;
    }
  }

  // ─── Paiement : création d'un ordre + URL CinetPay ───────────────────────

  /// Crée un ordre de paiement en DB (statut 'pending'), dans la devise du
  /// compte (fixée côté serveur à partir du pays de facturation).
  /// L'Edge Function `cinetpay-init-payment` consomme ensuite cet ordre pour
  /// générer l'URL de la page hosted CinetPay.
  Future<PaymentOrderDraft> createPaymentOrder({
    required String packCode,
    bool forEstablishment = false,
  }) async {
    dynamic res;
    try {
      res = await _client.rpc(
        'create_payment_order',
        params: {
          'p_pack_code': packCode,
          'p_target_kind': forEstablishment ? 'establishment' : 'user',
        },
      );
    } on sb.PostgrestException catch (e) {
      if (e.message.contains('BILLING_COUNTRY_REQUIRED')) {
        throw 'Choisissez d\'abord votre pays de facturation.';
      }
      rethrow;
    }
    final rows = (res as List?) ?? const <dynamic>[];
    if (rows.isEmpty) {
      throw 'Impossible de créer l\'ordre de paiement.';
    }
    final row = rows.first as Map<String, dynamic>;
    final currency = BillingCurrency.fromCode(row['out_currency']?.toString());
    if (currency == null) {
      throw 'Devise de commande inconnue (${row['out_currency']}).';
    }
    return PaymentOrderDraft(
      orderId: row['out_order_id']?.toString() ?? '',
      amount: (row['out_amount'] as num?)?.toInt() ?? 0,
      currency: currency,
      countryCode: (row['out_country'] ?? '').toString(),
      copiesCount: (row['out_copies_count'] as num?)?.toInt() ?? 0,
      packName: (row['out_pack_name'] ?? '').toString(),
    );
  }

  /// Initialise un paiement CinetPay. Appelle l'Edge Function
  /// `cinetpay-init-payment` qui retourne l'URL de la page hosted CinetPay.
  ///
  /// [phoneNumber] doit être au format international (ex: `+224622220700`).
  /// Il est obligatoire côté CinetPay : Orange Money / MTN / Wave envoient
  /// un SMS sur ce numéro pour confirmer le paiement.
  Future<String?> initCinetPayHostedUrl({
    required String orderId,
    required String paymentMethod, // 'OM','MTN','WAVE','MOOV','AIRTEL','CARD'
    required String phoneNumber, // ex: '+224622220700'
  }) async {
    try {
      final response = await _client.functions.invoke(
        'cinetpay-init-payment',
        body: {
          'order_id': orderId,
          'payment_method': paymentMethod,
          'phone_number': phoneNumber,
        },
      );
      final status = response.status ?? 0;
      if (status >= 200 && status < 300) {
        final data = response.data;
        if (data is Map && data['payment_url'] is String) {
          return data['payment_url'] as String;
        }
      }
      debugPrint(
          '[CreditsService.initCinetPay] status=$status data=${response.data}');
      return null;
    } catch (e) {
      debugPrint('[CreditsService.initCinetPay] erreur : $e');
      return null;
    }
  }

  // ─── Gestion quotas profs (admin only) ───────────────────────────────────

  Future<void> updateTeacherQuota(String userId, int limit) async {
    await _client.rpc(
      'update_teacher_quota',
      params: {'p_user_id': userId, 'p_limit': limit},
    );
    await Future.wait([refreshTeacherQuotas(), refreshWallet()]);
  }

  /// Michel : attribution additive. Ajoute [amount] au quota du prof et
  /// consomme le même montant du pool dispo côté admin. Lance si pool
  /// dispo insuffisant.
  Future<void> attributeCreditsToTeacher(String userId, int amount) async {
    await _client.rpc(
      'attribute_credits_to_teacher',
      params: {'p_user_id': userId, 'p_amount': amount},
    );
    await Future.wait([refreshTeacherQuotas(), refreshWallet()]);
  }

  /// Moyens de paiement proposés pour un pays donné (grille v5) :
  /// Mobile Money selon les opérateurs du pays + carte bancaire en XOF
  /// uniquement (pas encore disponible en GNF chez CinetPay).
  static List<PaymentMethod> paymentMethodsFor(BillingCountry country) {
    return paymentMethods
        .where((m) => m.code == 'CARD'
            ? country.cardAvailable
            : country.mobileOperators.contains(m.code))
        .toList();
  }

  /// Catalogue complet des moyens de paiement CinetPay connus de l'app.
  /// Utiliser [paymentMethodsFor] pour filtrer selon le pays du compte.
  static const List<PaymentMethod> paymentMethods = [
    PaymentMethod(
      code: 'OM',
      name: 'Orange Money',
      emoji: '🟠',
    ),
    PaymentMethod(code: 'MTN', name: 'MTN Mobile Money', emoji: '🟡'),
    PaymentMethod(code: 'WAVE', name: 'Wave', emoji: '🔵'),
    PaymentMethod(code: 'MOOV', name: 'Moov Money', emoji: '🔷'),
    PaymentMethod(code: 'AIRTEL', name: 'Airtel Money', emoji: '🔴'),
    PaymentMethod(
      code: 'CARD',
      name: 'Carte bancaire (Visa / Mastercard)',
      emoji: '💳',
    ),
  ];
}

class PaymentMethod {
  final String code;
  final String name;
  final String emoji;
  final String? hint;
  const PaymentMethod({
    required this.code,
    required this.name,
    required this.emoji,
    this.hint,
  });
}

