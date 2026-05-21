import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/copy.dart';
import '../models/exam.dart';

/// Résultat d'une correction par l'Edge Function.
class RemoteGradeResult {
  final bool success;
  final String? error;
  const RemoteGradeResult({required this.success, this.error});
}

/// Service de correction IA.
///
/// EN PROD : appelle l'Edge Function `grade-copy` (Claude + Vision côté serveur).
/// La fonction fait l'OCR, note la copie, et met à jour la DB directement.
///
/// FALLBACK : si l'Edge Function échoue, le mock local prend le relais.
class AiCorrectionService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Corrige une copie via l'Edge Function `grade-copy`.
  /// La fonction met à jour la copie en base — il suffit ensuite de la
  /// recharger côté app. Retourne le succès / l'erreur.
  Future<RemoteGradeResult> gradeCopyRemote(String copyId) async {
    try {
      final res = await _client.functions.invoke(
        'grade-copy',
        body: {'copyId': copyId},
      );
      final data = res.data;
      if (data != null && data['error'] != null) {
        return RemoteGradeResult(success: false, error: '${data['error']}');
      }
      return const RemoteGradeResult(success: true);
    } catch (e) {
      debugPrint('AiCorrectionService: grade-copy échoué. Cause: $e');
      return RemoteGradeResult(success: false, error: '$e');
    }
  }

  /// Génère un corrigé type à partir des questions (option C).
  Future<String> generateAnswerKey(Exam exam) async {
    await Future.delayed(const Duration(seconds: 2));
    final buffer = StringBuffer()..writeln('## Corrigé proposé\n');
    for (final q in exam.questions) {
      buffer.writeln(
          '### ${q.label}  (${q.totalPoints.toStringAsFixed(q.totalPoints == q.totalPoints.roundToDouble() ? 0 : 1)} pts)');
      if (q.statement.isNotEmpty) {
        buffer.writeln('> ${q.statement}');
      }
      if (q.isLeaf) {
        buffer.writeln('Éléments attendus : à compléter par le professeur.');
      } else {
        for (final sub in q.subQuestions) {
          buffer.writeln(
              '- **${sub.label}** (${sub.points.toStringAsFixed(sub.points == sub.points.roundToDouble() ? 0 : 1)} pts) — ${sub.statement.isEmpty ? "à compléter" : sub.statement}');
          buffer.writeln('  Réponse attendue : à compléter.');
        }
      }
      buffer.writeln();
    }
    buffer.writeln(
        '— Corrigé généré automatiquement, à valider par le professeur avant utilisation.');
    return buffer.toString();
  }

  /// Corrige une copie : retourne les notes par leaf + commentaire général.
  /// Chaque "leaf" est soit une question simple, soit une sous-question.
  Future<({List<QuestionGrade> grades, String generalComment, double confidence})>
      gradeCopy({required Exam exam, required StudentCopy copy}) async {
    // Simule un délai variable de traitement IA
    await Future.delayed(Duration(milliseconds: 1800 + Random().nextInt(2000)));
    final rng = Random(copy.id.hashCode);
    final grades = <QuestionGrade>[];
    for (final q in exam.questions) {
      if (q.isLeaf) {
        final ratio = 0.4 + rng.nextDouble() * 0.6;
        final score = (q.points * ratio * 2).round() / 2;
        grades.add(QuestionGrade(
          questionId: q.id,
          score: score.clamp(0, q.points).toDouble(),
          comment: _comment(rng, score, q.points),
        ));
      } else {
        for (final sub in q.subQuestions) {
          final ratio = 0.4 + rng.nextDouble() * 0.6;
          final score = (sub.points * ratio * 2).round() / 2;
          grades.add(QuestionGrade(
            questionId: sub.id,
            score: score.clamp(0, sub.points).toDouble(),
            comment: _comment(rng, score, sub.points),
          ));
        }
      }
    }
    final confidence = 0.65 + rng.nextDouble() * 0.3;
    final total = exam.computedTotal == 0 ? 1 : exam.computedTotal;
    final globalRatio = grades.fold<double>(0, (s, g) => s + g.score) / total;
    return (
      grades: grades,
      generalComment: _generalComment(globalRatio),
      confidence: confidence,
    );
  }

  String _comment(Random rng, double score, double max) {
    final ratio = max == 0 ? 0 : score / max;
    if (ratio >= 0.85) return 'Très bonne réponse, complète et bien argumentée.';
    if (ratio >= 0.65) return 'Réponse correcte, quelques points à approfondir.';
    if (ratio >= 0.4) return 'Réponse partielle, des notions sont manquantes.';
    return 'Réponse insuffisante ou hors sujet.';
  }

  String _generalComment(double ratio) {
    if (ratio >= 0.8) {
      return 'Travail solide, excellente maîtrise des notions clés.';
    }
    if (ratio >= 0.6) {
      return 'Bon travail dans l\'ensemble, à consolider sur certains points.';
    }
    if (ratio >= 0.4) {
      return 'Travail moyen, plusieurs notions à revoir.';
    }
    return 'Beaucoup de difficultés — un suivi personnalisé est recommandé.';
  }
}
