import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// État de la suppression du compte connecté (RPC `get_my_account_deletion`).
class AccountDeletionStatus {
  final DateTime? requestedAt;
  final DateTime? scheduledFor;

  /// `SCHOOL_OWNER` ou `SOLE_ADMIN` si la suppression est impossible.
  final String? blocker;

  /// Le prof a des examens rattachés à une école (ils y resteront).
  final bool inSchool;

  const AccountDeletionStatus({
    this.requestedAt,
    this.scheduledFor,
    this.blocker,
    this.inSchool = false,
  });

  bool get isPending => scheduledFor != null;
  bool get isBlocked => blocker != null;
}

/// Suppression de compte (exigence Google Play).
///
/// Règles (validées le 15/10/2026) : la demande déclenche une suppression
/// définitive 30 jours plus tard ; le compte peut annuler pendant ce délai en
/// se reconnectant. La purge est faite côté serveur par le job quotidien.
class AccountDeletionService {
  AccountDeletionService._();

  static SupabaseClient get _client => Supabase.instance.client;

  static DateTime? _parse(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// Null si personne n'est connecté ou si la lecture échoue.
  static Future<AccountDeletionStatus?> status() async {
    if (_client.auth.currentUser == null) return null;
    try {
      final res = await _client.rpc('get_my_account_deletion');
      final rows = res is List ? res : [res];
      if (rows.isEmpty || rows.first == null) {
        return const AccountDeletionStatus();
      }
      final r = Map<String, dynamic>.from(rows.first as Map);
      return AccountDeletionStatus(
        requestedAt: _parse(r['out_requested_at']),
        scheduledFor: _parse(r['out_scheduled_for']),
        blocker: r['out_blocker'] as String?,
        inSchool: r['out_in_school'] == true,
      );
    } catch (e) {
      debugPrint('[AccountDeletionService.status] $e');
      return null;
    }
  }

  /// Demande la suppression. Renvoie la date de suppression définitive.
  /// Lève une [AccountDeletionException] avec un message lisible si refusé.
  static Future<DateTime> request() async {
    try {
      final res = await _client.rpc('request_account_deletion');
      return _parse(res) ?? DateTime.now().add(const Duration(days: 30));
    } on PostgrestException catch (e) {
      throw AccountDeletionException(messageFor(e.message));
    }
  }

  /// Annule une demande en cours.
  static Future<void> cancel() async {
    await _client.rpc('cancel_account_deletion');
  }

  static String messageFor(String? code) {
    switch (code) {
      case 'SCHOOL_OWNER':
        return 'Vous êtes propriétaire d\'une école. Contactez le support '
            'pour transférer ou fermer l\'école avant de supprimer votre compte.';
      case 'SOLE_ADMIN':
        return 'Vous êtes le seul administrateur d\'une école. Nommez un autre '
            'administrateur ou contactez le support avant de supprimer votre compte.';
      default:
        return 'La suppression n\'a pas pu être demandée. Réessayez ou '
            'contactez le support.';
    }
  }

  static String formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }
}

class AccountDeletionException implements Exception {
  final String message;
  AccountDeletionException(this.message);
  @override
  String toString() => message;
}
