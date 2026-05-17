import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../models/correction_source.dart';
import '../../models/exam.dart';
import '../../services/exam_service.dart';
import '../../services/export_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';
import '../scan/new_student_screen.dart';
import 'correction_source_screen.dart';
import 'ranking_screen.dart';
import 'student_copy_detail_screen.dart';
import 'subject_validation_screen.dart';

/// Écran central d'un examen : statut, source, liste des copies, export.
class ExamDetailScreen extends StatelessWidget {
  final String examId;
  const ExamDetailScreen({super.key, required this.examId});

  @override
  Widget build(BuildContext context) {
    final examSvc = context.watch<ExamService>();
    final exam = examSvc.getExam(examId);
    if (exam == null) {
      return const Scaffold(body: Center(child: Text('Examen introuvable')));
    }
    final copies = examSvc.copiesFor(examId);
    final graded =
        copies.where((c) => c.status == CopyStatus.graded).length;
    final canScan = exam.isReadyForScan;

    return Scaffold(
      body: Column(
        children: [
          RoundedHeader(
            height: 240,
            showBackButton: true,
            actions: [
              HeaderCircleAction(
                icon: Icons.delete_outline,
                tooltip: 'Supprimer',
                onPressed: () => _confirmDelete(context, examId),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'EXAMEN',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          letterSpacing: 1.5,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    exam.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (exam.className?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      exam.className!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MetaBadge(
                        text: '${exam.language.flag} ${exam.language.label}',
                      ),
                      const SizedBox(width: 6),
                      _MetaBadge(
                        text: '${exam.examType.emoji} ${exam.examType.label}',
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      _Stat(
                        label: 'Notées',
                        value: '$graded',
                        icon: Icons.check_circle,
                      ),
                      const SizedBox(width: 18),
                      _Stat(
                        label: 'Total',
                        value: '${copies.length}',
                        icon: Icons.people_alt,
                      ),
                      const SizedBox(width: 18),
                      _Stat(
                        label: 'Sur',
                        value: exam.computedTotal == 0
                            ? exam.totalPoints.toStringAsFixed(0)
                            : exam.computedTotal.toStringAsFixed(
                                exam.computedTotal == exam.computedTotal.roundToDouble()
                                    ? 0
                                    : 2),
                        icon: Icons.grade,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
              children: [
                // Étapes / config
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Configuration',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      _ConfigRow(
                        icon: Icons.assignment_outlined,
                        label: 'Sujet',
                        value: exam.subjectValidated
                            ? '${exam.questions.length} questions validées'
                            : 'À valider',
                        valid: exam.subjectValidated,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              SubjectValidationScreen(examId: examId),
                        )),
                      ),
                      const Divider(height: 24),
                      _ConfigRow(
                        icon: Icons.school_outlined,
                        label: 'Source de correction',
                        value: exam.correctionSource == null
                            ? 'À définir'
                            : _sourceLabel(exam.correctionSource!),
                        valid: exam.correctionSource != null &&
                            (exam.correctionSource!.type !=
                                    CorrectionSourceType.aiGenerated ||
                                exam.correctionSource!.validated),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              CorrectionSourceScreen(examId: examId),
                        )),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // Copies
                Row(
                  children: [
                    Text(
                      'Copies des élèves',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (copies.isNotEmpty && canScan)
                      TextButton.icon(
                        onPressed: () => _exportExcel(context, examId),
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Excel'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (copies.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RankingButton(examId: examId),
                  ),
                if (copies.isEmpty)
                  _EmptyCopies(canScan: canScan)
                else
                  ...copies.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CopyTile(
                        copy: c,
                        totalPoints: exam.computedTotal == 0
                            ? exam.totalPoints
                            : exam.computedTotal,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              StudentCopyDetailScreen(copyId: c.id),
                        )),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: canScan
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PrimaryButton(
                  label: 'Scanner une copie',
                  icon: Icons.qr_code_scanner,
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => NewStudentScreen(examId: examId),
                  )),
                ),
              ),
            )
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          exam.subjectValidated
                              ? 'Définissez et validez la source de correction pour démarrer.'
                              : 'Validez d\'abord le sujet (questions + barème).',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  static String _sourceLabel(CorrectionSource s) {
    final base = s.type.title;
    switch (s.type) {
      case CorrectionSourceType.answerKey:
      case CorrectionSourceType.course:
        return '$base • ${s.documentPaths.length} doc(s)';
      case CorrectionSourceType.aiGenerated:
        return '$base • ${s.validated ? "validé" : "à valider"}';
    }
  }

  static Future<void> _confirmDelete(
      BuildContext context, String examId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title: const Text('Supprimer cet examen ?'),
        content: const Text(
          'Toutes les copies et notes associées seront supprimées. Action irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<ExamService>().deleteExam(examId);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  static Future<void> _exportExcel(
      BuildContext context, String examId) async {
    final svc = context.read<ExamService>();
    final exam = svc.getExam(examId);
    if (exam == null) return;
    final copies = svc.copiesFor(examId);
    if (copies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune copie à exporter.')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Génération du fichier Excel...'),
        duration: Duration(seconds: 1),
      ),
    );
    try {
      final exporter = ExportService();
      final file = await exporter.exportToExcel(exam: exam, copies: copies);
      await exporter.shareFile(file,
          subject: 'Résultats Correctis – ${exam.title}');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Échec de l\'export : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}

class _RankingButton extends StatelessWidget {
  final String examId;
  const _RankingButton({required this.examId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RankingScreen(examId: examId),
      )),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              AppColors.primary,
              AppColors.primaryLight,
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Générer le classement',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Voir le podium et exporter en Excel',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final String text;
  const _MetaBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Stat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool valid;
  final VoidCallback onTap;

  const _ConfigRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.valid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (valid ? AppColors.success : AppColors.warning)
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon,
                color: valid ? AppColors.success : AppColors.warning),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _EmptyCopies extends StatelessWidget {
  final bool canScan;
  const _EmptyCopies({required this.canScan});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        children: [
          const Icon(Icons.people_outline,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Aucune copie scannée',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            canScan
                ? 'Cliquez sur "Scanner une copie" pour commencer.'
                : 'Configurez d\'abord le sujet et la source de correction.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CopyTile extends StatelessWidget {
  final StudentCopy copy;
  final double totalPoints;
  final VoidCallback onTap;
  const _CopyTile({
    required this.copy,
    required this.totalPoints,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isGraded = copy.status == CopyStatus.graded;
    final percent = totalPoints == 0
        ? 0.0
        : (copy.totalScore / totalPoints).clamp(0, 1).toDouble();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  _initials(copy.studentName),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.studentName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusChip(status: copy.status),
                        const SizedBox(width: 8),
                        Text(
                          '${copy.pageImages.length} page${copy.pageImages.length > 1 ? 's' : ''}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isGraded)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_fmt(copy.totalScore)}/${_fmt(totalPoints)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      '${(percent * 100).toStringAsFixed(0)} %',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}
