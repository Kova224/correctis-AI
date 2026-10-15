import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';

/// A7 (Sprint 5) — Onglet Résultats avec analyse des lacunes.
///
/// Pour chaque examen où au moins 3 copies ont été corrigées, on calcule :
///   • La moyenne générale de la classe
///   • Les questions les moins réussies (moyenne < 50 % du barème)
///     → ce sont les "lacunes" à retravailler avec la classe
///
/// Le prof voit d'un coup d'œil ce qui a mal marché sur chaque examen,
/// avec le libellé de la question et son score moyen.
class ResultsBody extends StatelessWidget {
  const ResultsBody({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final examSvc = context.watch<ExamService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    // On considère un examen "significatif" à partir de 3 copies notées.
    final exams = examSvc.examsForUser(user.id);
    final analyses = <_ExamAnalysis>[];
    for (final exam in exams) {
      final copies = examSvc
          .copiesFor(exam.id)
          .where((c) => c.gradedAt != null && c.grades.isNotEmpty)
          .toList();
      if (copies.length < 3) continue;
      analyses.add(_analyzeExam(exam, copies));
    }
    analyses.sort((a, b) => b.exam.updatedAt.compareTo(a.exam.updatedAt));

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.profPrimary,
        backgroundColor: AppColors.card,
        onRefresh: () async => examSvc.bootstrap(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          children: [
            Text(
              'RÉSULTATS · ANALYSE DE CLASSE',
              style: AppFonts.mono(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lacunes par examen',
              style: AppFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Les questions les moins réussies sont extraites automatiquement '
              'pour chaque examen ayant au moins 3 copies notées.',
              style: AppFonts.sans(
                fontSize: 12.5,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            if (analyses.isEmpty)
              _emptyState()
            else
              ...analyses.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _ExamAnalysisCard(analysis: a),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.profPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.insights_rounded,
              color: AppColors.profPrimary,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Pas encore d\'analyse',
            style: AppFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Corrigez au moins 3 copies d\'un examen pour voir apparaître '
            'les lacunes de la classe.',
            style: AppFonts.sans(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  static _ExamAnalysis _analyzeExam(Exam exam, List<StudentCopy> copies) {
    // Aplati la liste des feuilles gradables
    final leaves = <Question>[];
    for (final q in exam.questions) {
      if (q.isLeaf) {
        leaves.add(q);
      } else {
        for (final sub in q.subQuestions) {
          leaves.add(Question(
            id: sub.id,
            label: '${q.label}.${sub.label}',
            statement: sub.statement,
            points: sub.points,
          ));
        }
      }
    }

    // Score par feuille + moyenne
    final avgByLeaf = <String, _LeafScore>{};
    for (final leaf in leaves) {
      double sum = 0;
      int count = 0;
      for (final c in copies) {
        final g = c.grades.firstWhere(
          (g) => g.questionId == leaf.id,
          orElse: () =>
              QuestionGrade(questionId: leaf.id, score: 0),
        );
        sum += g.score;
        count++;
      }
      final avg = count > 0 ? sum / count : 0;
      avgByLeaf[leaf.id] = _LeafScore(
        leaf: leaf,
        avgScore: avg.toDouble(),
        fractionMastered: leaf.points > 0 ? avg / leaf.points : 0,
      );
    }

    // Moyenne générale (sur 20)
    final totalMax = leaves.fold<double>(0, (s, l) => s + l.points);
    double totalSum = 0;
    for (final c in copies) {
      double sc = 0;
      for (final g in c.grades) {
        sc += g.score;
      }
      totalSum += sc;
    }
    final classAvg20 = totalMax > 0
        ? (totalSum / copies.length) / totalMax * 20
        : 0;

    // Lacunes = questions dont fraction < 0.5
    final lacunes = avgByLeaf.values
        .where((v) => v.fractionMastered < 0.5)
        .toList()
      ..sort((a, b) =>
          a.fractionMastered.compareTo(b.fractionMastered)); // pire en premier

    return _ExamAnalysis(
      exam: exam,
      copiesCount: copies.length,
      classAverage20: classAvg20.toDouble(),
      lacunes: lacunes,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Types internes
// ══════════════════════════════════════════════════════════════════════════

class _ExamAnalysis {
  final Exam exam;
  final int copiesCount;
  final double classAverage20;
  final List<_LeafScore> lacunes;

  const _ExamAnalysis({
    required this.exam,
    required this.copiesCount,
    required this.classAverage20,
    required this.lacunes,
  });
}

class _LeafScore {
  final Question leaf;
  final double avgScore;
  final double fractionMastered; // 0..1

  const _LeafScore({
    required this.leaf,
    required this.avgScore,
    required this.fractionMastered,
  });
}

// ══════════════════════════════════════════════════════════════════════════
// UI
// ══════════════════════════════════════════════════════════════════════════

class _ExamAnalysisCard extends StatelessWidget {
  final _ExamAnalysis analysis;
  const _ExamAnalysisCard({required this.analysis});

  Color _avgColor(double n20) {
    if (n20 >= 14) return AppColors.profPrimary;
    if (n20 >= 10) return AppColors.primaryLight;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final e = analysis.exam;
    final avgColor = _avgColor(analysis.classAverage20);
    final hasLacunes = analysis.lacunes.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header : titre + classe
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      style: AppFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((e.className ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        e.className!,
                        style: AppFonts.sans(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    analysis.classAverage20.toStringAsFixed(1),
                    style: AppFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: avgColor,
                    ),
                  ),
                  Text(
                    '/ 20 · moyenne',
                    style: AppFonts.mono(
                      fontSize: 9,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.groups_2_outlined,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                '${analysis.copiesCount} copies notées',
                style: AppFonts.sans(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.borderSubtle, height: 1),
          const SizedBox(height: 12),

          // Section lacunes
          Row(
            children: [
              Icon(
                hasLacunes
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                size: 14,
                color: hasLacunes
                    ? AppColors.warning
                    : AppColors.profPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                hasLacunes ? 'LACUNES DÉTECTÉES' : 'AUCUNE LACUNE',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: hasLacunes
                      ? AppColors.warning
                      : AppColors.profPrimary,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasLacunes)
            Text(
              'Toutes les questions ont été majoritairement réussies.',
              style: AppFonts.sans(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            )
          else
            ...analysis.lacunes.take(5).map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _LacuneRow(leaf: l),
                )),
          if (analysis.lacunes.length > 5) ...[
            const SizedBox(height: 4),
            Text(
              '+ ${analysis.lacunes.length - 5} autres questions à retravailler',
              style: AppFonts.sans(
                fontSize: 10.5,
                color: AppColors.textMuted,
              ).copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

class _LacuneRow extends StatelessWidget {
  final _LeafScore leaf;
  const _LacuneRow({required this.leaf});

  @override
  Widget build(BuildContext context) {
    final pct = (leaf.fractionMastered * 100).round();
    final labelStatement = leaf.leaf.statement.trim().isEmpty
        ? 'Question ${leaf.leaf.label}'
        : leaf.leaf.statement;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'Q${leaf.leaf.label}',
            style: AppFonts.mono(
              fontSize: 9,
              color: AppColors.warning,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            labelStatement.length > 90
                ? '${labelStatement.substring(0, 90)}…'
                : labelStatement,
            style: AppFonts.sans(
              fontSize: 11.5,
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$pct%',
          style: AppFonts.fraunces(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: pct < 25 ? AppColors.danger : AppColors.warning,
          ),
        ),
      ],
    );
  }
}
