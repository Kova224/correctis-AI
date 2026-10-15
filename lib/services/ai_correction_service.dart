import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/exam.dart';

/// Résultat d'une correction par l'Edge Function.
class RemoteGradeResult {
  final bool success;
  final String? error;
  const RemoteGradeResult({required this.success, this.error});
}

/// Service de correction IA.
///
/// L'unique chemin de correction est l'Edge Function `grade-copy` qui fait
/// OCR + notation Claude et met à jour la copie en base.
///
/// ⚠️ Pas de fallback mock — si l'Edge Function échoue, la copie passe en
/// statut ERROR et le prof voit l'erreur. C'est volontaire : un mock qui
/// invente des notes masquerait silencieusement les vrais bugs.
class AiCorrectionService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Corrige une copie via l'Edge Function `grade-copy`.
  /// La fonction met à jour la copie en base — il suffit ensuite de la
  /// recharger côté app. Retourne le succès / l'erreur.
  Future<RemoteGradeResult> gradeCopyRemote(
    String copyId, {
    List<Map<String, dynamic>>? manualCorrections,
  }) async {
    debugPrint('[gradeCopyRemote] → invoke grade-copy avec copyId=$copyId'
        '${manualCorrections != null ? ' + ${manualCorrections.length} HIL' : ''}');
    try {
      final body = <String, dynamic>{'copyId': copyId};
      if (manualCorrections != null && manualCorrections.isNotEmpty) {
        body['manualCorrections'] = manualCorrections;
      }
      final res = await _client.functions.invoke(
        'grade-copy',
        body: body,
      );
      debugPrint(
          '[gradeCopyRemote] ← status=${res.status} data_type=${res.data?.runtimeType}');

      // Status HTTP non-2xx → erreur explicite
      if (res.status != null && (res.status! < 200 || res.status! >= 300)) {
        // Tente de récupérer le message d'erreur du body
        String errMsg = 'HTTP ${res.status}';
        final data = res.data;
        if (data is Map && data['error'] != null) {
          errMsg = '${data['error']}';
        } else if (data is String && data.isNotEmpty) {
          errMsg = data;
        }
        debugPrint('[gradeCopyRemote] ← erreur HTTP: $errMsg');
        return RemoteGradeResult(success: false, error: errMsg);
      }

      final data = res.data;
      // Si le body contient {error: "..."}, c'est une erreur métier
      if (data is Map && data['error'] != null) {
        debugPrint('[gradeCopyRemote] ← erreur métier: ${data['error']}');
        return RemoteGradeResult(success: false, error: '${data['error']}');
      }
      // Si le body est null ou ne contient pas grades/correction_detaillee,
      // la fonction n'a probablement pas fait son job
      if (data == null) {
        return const RemoteGradeResult(
            success: false, error: 'Réponse vide de l\'Edge Function.');
      }
      debugPrint('[gradeCopyRemote] ← OK');
      return const RemoteGradeResult(success: true);
    } on FunctionException catch (e) {
      debugPrint('[gradeCopyRemote] ← FunctionException: ${e.toString()}');
      return RemoteGradeResult(
          success: false,
          error: 'Edge Function indisponible : ${e.details ?? e.reasonPhrase ?? e.status}');
    } catch (e) {
      debugPrint('[gradeCopyRemote] ← exception: $e');
      return RemoteGradeResult(success: false, error: '$e');
    }
  }

  /// Génère un corrigé type avec Claude (option C « Génération IA »).
  ///
  /// Appelle l'Edge Function `generate-answer-key`, qui lit le sujet et le
  /// barème validés de l'examen. Le prof doit relire et VALIDER le texte
  /// avant la correction des copies. Lance une erreur lisible en cas
  /// d'échec (limite atteinte, IA indisponible…).
  Future<String> generateAnswerKey(Exam exam) async {
    try {
      final res = await _client.functions.invoke(
        'generate-answer-key',
        body: {'examId': exam.id},
      );
      final data = res.data;
      if (data is Map && data['content'] is String &&
          (data['content'] as String).trim().isNotEmpty) {
        return data['content'] as String;
      }
      if (data is Map && data['error'] != null) {
        throw '${data['error']}';
      }
      throw 'Réponse vide du service de génération.';
    } on FunctionException catch (e) {
      final details = e.details;
      if (details is Map && details['error'] != null) {
        throw '${details['error']}';
      }
      throw 'Génération impossible (${e.status}). Réessayez dans un instant.';
    }
  }
}
