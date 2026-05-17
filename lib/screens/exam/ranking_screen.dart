import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../services/exam_service.dart';
import '../../services/export_service.dart';
import '../../services/ranking_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';

/// Écran de classement d'un examen avec podium top 3 + liste + export Excel.
class RankingScreen extends StatelessWidget {
  final String examId;
  const RankingScreen({super.key, required this.examId});

  @override
  Widget build(BuildContext context) {
    final examSvc = context.watch<ExamService>();
    final exam = examSvc.getExam(examId);
    if (exam == null) {
      return const Scaffold(body: Center(child: Text('Examen introuvable')));
    }
    final copies = examSvc.copiesFor(examId);
    final ranking = RankingService().rankExam(exam, copies);
    final ranked = ranking.where((e) => e.position > 0).toList();
    final notRanked = ranking.where((e) => e.position == 0).toList();
    final allGraded =
        copies.isNotEmpty && copies.every((c) => c.status == CopyStatus.graded);

    return Scaffold(
      body: Column(
        children: [
          RoundedHeader(
            height: 240,
            showBackButton: true,
            actions: [
              if (ranked.isNotEmpty)
                HeaderCircleAction(
                  icon: Icons.download_rounded,
                  tooltip: 'Exporter Excel',
                  onPressed: () => _exportExcel(context, exam, ranking),
                ),
            ],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: Colors.white, size: 38),
                  const SizedBox(height: 8),
                  Text(
                    'CLASSEMENT',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    exam.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (exam.className?.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      exam.className!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ranked.isEmpty
                ? _emptyState(context, copies.isEmpty)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
                    children: [
                      if (!allGraded)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: AppColors.warning, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Classement provisoire — ${notRanked.length} copie(s) en attente de correction.',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Podium top 3
                      if (ranked.length >= 3)
                        _Podium(top3: ranked.take(3).toList()),
                      const SizedBox(height: 18),
                      // Liste classée
                      Text(
                        ranked.length >= 3
                            ? 'Suite du classement'
                            : 'Classement complet',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 10),
                      ...List.generate(
                        ranked.length >= 3
                            ? ranked.length - 3
                            : ranked.length,
                        (i) {
                          final entry = ranked[ranked.length >= 3 ? i + 3 : i];
                          return _RankRow(entry: entry);
                        },
                      ),
                      if (notRanked.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'En attente de correction',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 8),
                        ...notRanked.map(
                            (e) => _RankRow(entry: e, dimmed: true)),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: ranked.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PrimaryButton(
                  label: 'Exporter en Excel',
                  icon: Icons.download_rounded,
                  onPressed: () => _exportExcel(context, exam, ranking),
                ),
              ),
            )
          : null,
    );
  }

  Widget _emptyState(BuildContext context, bool noCopies) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_outlined,
                  size: 50, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              noCopies ? 'Aucune copie scannée' : 'Aucune copie corrigée',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              noCopies
                  ? 'Scannez d\'abord les copies des élèves, puis générez le classement.'
                  : 'Le classement apparaîtra dès que les copies seront corrigées par l\'IA.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportExcel(
    BuildContext context,
    dynamic exam,
    List<RankingEntry> ranking,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Génération du fichier Excel...'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final exporter = ExportService();
      final file = await exporter.exportRankingToExcel(
        exam: exam,
        ranking: ranking,
      );
      await exporter.shareFile(file,
          subject: 'Classement Correctis – ${exam.title}');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Échec : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

// =============================================================================
// PODIUM TOP 3
// =============================================================================
class _Podium extends StatelessWidget {
  final List<RankingEntry> top3;
  const _Podium({required this.top3});

  @override
  Widget build(BuildContext context) {
    final p1 = top3[0];
    final p2 = top3[1];
    final p3 = top3[2];
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
      child: Column(
        children: [
          // Avatars
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PodiumPlace(entry: p2, height: 110, color: const Color(0xFFC0C0C0), trophy: '🥈'),
              _PodiumPlace(entry: p1, height: 140, color: const Color(0xFFFFD700), trophy: '🥇', main: true),
              _PodiumPlace(entry: p3, height: 90, color: const Color(0xFFCD7F32), trophy: '🥉'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PodiumPlace extends StatelessWidget {
  final RankingEntry entry;
  final double height;
  final Color color;
  final String trophy;
  final bool main;

  const _PodiumPlace({
    required this.entry,
    required this.height,
    required this.color,
    required this.trophy,
    this.main = false,
  });

  String get _initials {
    final parts =
        entry.studentName.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(trophy, style: TextStyle(fontSize: main ? 28 : 22)),
          const SizedBox(height: 4),
          Container(
            width: main ? 56 : 44,
            height: main ? 56 : 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.7)],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _initials,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: main ? 18 : 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            entry.studentName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: main ? 13 : 11,
            ),
          ),
          Text(
            '${_fmt(entry.score)}/${_fmt(entry.maxScore)}',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: main ? 12 : 10,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color, color.withValues(alpha: 0.65)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Center(
              child: Text(
                '${entry.position}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: main ? 32 : 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// LIGNE DE CLASSEMENT
// =============================================================================
class _RankRow extends StatelessWidget {
  final RankingEntry entry;
  final bool dimmed;
  const _RankRow({required this.entry, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final mentionColor = _mentionColor(entry.percent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: dimmed
                ? AppColors.divider
                : AppColors.primary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            // Position
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: dimmed
                    ? AppColors.surfaceMuted
                    : AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  entry.position == 0 ? '—' : '${entry.position}',
                  style: TextStyle(
                    color: dimmed ? AppColors.textMuted : AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.studentName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color:
                          dimmed ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                  if (entry.mention != null && !dimmed) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.mention!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: mentionColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ] else if (dimmed)
                    Text(
                      entry.status.label,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
            if (!dimmed) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_fmt(entry.score)}/${_fmt(entry.maxScore)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    '${entry.percent.toStringAsFixed(0)} %',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _mentionColor(double pct) {
    if (pct >= 80) return AppColors.success;
    if (pct >= 70) return AppColors.primary;
    if (pct >= 60) return AppColors.accentDark;
    if (pct >= 50) return AppColors.warning;
    return AppColors.danger;
  }
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}
