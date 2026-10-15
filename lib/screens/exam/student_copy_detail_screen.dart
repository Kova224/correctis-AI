import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/billing.dart';
import '../../models/copy.dart';
import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/copy_image_fullscreen.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import '../../widgets/smart_image.dart';
import '../../widgets/status_chip.dart';
import 'correction_ia_screen.dart';
import 'illegible_zones_screen.dart';

/// Détail d'une copie : note par question, commentaires, image en regard,
/// modification manuelle (cahier §3.6).
class StudentCopyDetailScreen extends StatefulWidget {
  final String copyId;
  const StudentCopyDetailScreen({super.key, required this.copyId});

  @override
  State<StudentCopyDetailScreen> createState() =>
      _StudentCopyDetailScreenState();
}

class _StudentCopyDetailScreenState extends State<StudentCopyDetailScreen> {
  bool _editing = false;

  Future<void> _confirmDeleteCopy(BuildContext context, String copyId) async {
    final copy = context.read<ExamService>().getCopy(copyId);
    if (copy == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title: const Text('Supprimer cette copie ?'),
        content: Text(
          'La copie de "${copy.studentName}" et toutes ses notes seront '
          'définitivement supprimées. Cette action est irréversible.',
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
    if (ok != true) return;
    if (!context.mounted) return;
    try {
      final result = await context.read<ExamService>().deleteCopy(copyId);
      if (!context.mounted) return;
      Navigator.of(context).pop();

      // B2 : message adapté selon le type de suppression
      if (result == 'ARCHIVED') {
        // Note publiée >= 3 jours : soft delete côté prof, note conservée
        // dans le casier admin.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Copie de "${copy.studentName}" retirée de vos copies.\n'
              'La note reste dans le casier de l\'école (publiée depuis '
              'plus de 3 jours).',
            ),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        // 'DELETED' : suppression physique (copie non publiée ou < 3 jours)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Copie de "${copy.studentName}" supprimée.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suppression impossible : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final examSvc = context.watch<ExamService>();
    final copy = examSvc.getCopy(widget.copyId);
    if (copy == null) {
      return const Scaffold(body: Center(child: Text('Copie introuvable')));
    }
    final exam = examSvc.getExam(copy.examId)!;
    final total = exam.computedTotal == 0 ? exam.totalPoints : exam.computedTotal;

    return Scaffold(
      body: Column(
        children: [
          RoundedHeader(
            height: 240,
            showBackButton: true,
            actions: [
              if (copy.status == CopyStatus.graded)
                IconButton(
                  icon: Icon(_editing ? Icons.check : Icons.edit_outlined,
                      color: Colors.white),
                  tooltip: copy.isLocked
                      ? 'Notes figées (publiées au casier)'
                      : (_editing
                          ? 'Terminer la modification'
                          : 'Modifier les notes'),
                  onPressed: () {
                    // Notes figées 3 jours après la publication au casier
                    // (règle appliquée aussi côté base : COPY_LOCKED).
                    if (copy.isLocked && !_editing) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Notes figées : cette copie est publiée au casier '
                            'de l\'école depuis plus de 3 jours. Contactez '
                            'l\'administrateur pour une correction.',
                          ),
                        ),
                      );
                      return;
                    }
                    setState(() => _editing = !_editing);
                  },
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                tooltip: 'Supprimer cette copie',
                onPressed: () => _confirmDeleteCopy(context, copy.id),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'COPIE',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    copy.studentName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  if (copy.studentRef != null)
                    Text(
                      copy.studentRef!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        copy.status == CopyStatus.graded
                            ? '${_fmt(copy.totalScore)}'
                            : '—',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '/ ${_fmt(total)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const Spacer(),
                      StatusChip(status: copy.status),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                if (copy.status == CopyStatus.processing) ...[
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Correction en cours par l\'IA…',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vous pouvez fermer l\'application — '
                          'la correction continue côté serveur. '
                          'Revenez dans quelques minutes pour voir la note.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (copy.pageImages.isNotEmpty) ...[
                  Row(
                    children: [
                      Text(
                        'Pages scannées',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 14,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'touchez pour agrandir',
                        style: AppFonts.sans(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: copy.pageImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final path = copy.pageImages[i];
                        return GestureDetector(
                          onTap: () => CopyImageFullscreen.open(
                            context,
                            pages: copy.pageImages,
                            initialPage: i,
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SmartImage(
                                  path: path,
                                  width: 130,
                                  height: 180,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                bottom: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.zoom_in_rounded,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'p.${i + 1}',
                                        style: AppFonts.mono(
                                          fontSize: 9,
                                          color: Colors.white,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (copy.status == CopyStatus.graded) ...[
                  // Bandeau ZONES ILLISIBLES — si l'IA a marqué des zones
                  if (copy.grades.any(
                      (g) => g.comment.startsWith('[ZONE_ILLISIBLE]'))) ...[
                    _IllegibleZonesBanner(
                      count: copy.grades
                          .where(
                              (g) => g.comment.startsWith('[ZONE_ILLISIBLE]'))
                          .length,
                      onResolve: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              IllegibleZonesScreen(copyId: copy.id),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  // Bandeau HORS-SUJET si la copie a été rejetée par l'IA
                  if (copy.generalComment.startsWith('⛔ HORS-SUJET — ')) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AppColors.danger,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.report_gmailerrorred_outlined,
                            color: AppColors.danger,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'COPIE HORS-SUJET — REJETÉE',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: AppColors.danger,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  copy.generalComment.substring(
                                    '⛔ HORS-SUJET — '.length,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Aucune note attribuée. Vérifiez le sujet et la copie, ou modifiez manuellement si l\'IA s\'est trompée.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Notes par question',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            if (_editing)
                              const Chip(
                                label: Text('Mode édition'),
                                backgroundColor: Color(0xFFFFF7E6),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...exam.questions.map((q) {
                          return _QuestionGradeBlock(
                            question: q,
                            copy: copy,
                            editing: _editing,
                            onChanged: () async {
                              await context
                                  .read<ExamService>()
                                  .updateCopy(copy);
                              if (mounted) setState(() {});
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Commentaire général',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        if (_editing)
                          TextFormField(
                            initialValue: copy.generalComment,
                            maxLines: 4,
                            onChanged: (v) => copy.generalComment = v,
                            onFieldSubmitted: (_) async {
                              await context
                                  .read<ExamService>()
                                  .updateCopy(copy);
                            },
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: AppColors.surfaceMuted,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(16)),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(16)),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.all(14),
                            ),
                          )
                        else
                          Text(
                            copy.generalComment.isEmpty
                                ? 'Aucun commentaire général.'
                                : copy.generalComment.startsWith(
                                        '⛔ HORS-SUJET — ')
                                    ? copy.generalComment.substring(
                                        '⛔ HORS-SUJET — '.length)
                                    : copy.generalComment,
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Icon(Icons.psychology_outlined,
                                size: 16, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              'Confiance IA : ${(copy.confidence * 100).toStringAsFixed(0)} %',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else if (copy.status == CopyStatus.pending) ...[
                  SectionCard(
                    child: Column(
                      children: [
                        const Icon(Icons.hourglass_empty,
                            color: AppColors.textMuted, size: 36),
                        const SizedBox(height: 8),
                        const Text(
                          'En attente de correction',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Lancez la correction maintenant : '
                          '${copy.pageImages.length} page${copy.pageImages.length > 1 ? 's' : ''} '
                          '→ ${CreditRules.creditsLabel(CreditRules.creditsForPages(copy.pageImages.length))}.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: 'Lancer la correction',
                          icon: Icons.auto_awesome,
                          onPressed: () {
                            context.read<ExamService>().startCorrection(
                                  copy.id,
                                );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CorrectionIAScreen(
                                  examId: copy.examId,
                                  copyId: copy.id,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ] else if (copy.status == CopyStatus.error)
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.refresh_rounded,
                                color: AppColors.danger, size: 30),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Correction à reprendre',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.danger,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'La correction n\'a pas pu se terminer. '
                          'Appuyez sur "Reprendre" pour relancer — '
                          'elle continuera côté serveur, vous pouvez '
                          'fermer l\'app si besoin.\n'
                          'Les crédits réservés pour un échec technique sont '
                          'réutilisés à la reprise ou remis en solde '
                          'automatiquement. Cette copie nécessite '
                          '${CreditRules.creditsLabel(CreditRules.creditsForPages(copy.pageImages.length))}.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () {
                            context.read<ExamService>().startCorrection(
                                  copy.id,
                                );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CorrectionIAScreen(
                                  examId: copy.examId,
                                  copyId: copy.id,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reprendre la correction'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

/// Bloc d'affichage des notes pour une question (avec ou sans sous-questions).
class _QuestionGradeBlock extends StatelessWidget {
  final Question question;
  final StudentCopy copy;
  final bool editing;
  final VoidCallback onChanged;

  const _QuestionGradeBlock({
    required this.question,
    required this.copy,
    required this.editing,
    required this.onChanged,
  });

  QuestionGrade _gradeFor(String leafId) {
    return copy.grades.firstWhere(
      (g) => g.questionId == leafId,
      orElse: () => QuestionGrade(questionId: leafId, score: 0),
    );
  }

  void _setGrade(
    String leafId,
    double score,
    String comment,
    double max,
  ) {
    final grade = _gradeFor(leafId);
    grade.score = score.clamp(0, max).toDouble();
    grade.comment = comment;
    if (!copy.grades.any((g) => g.questionId == leafId)) {
      copy.grades.add(grade);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isLeaf = question.isLeaf;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Text(
                  question.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                      fontSize: 15),
                ),
              ),
              Text(
                '${_fmt(_totalScore())}/${_fmt(question.totalPoints)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (question.statement.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              question.statement,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (isLeaf)
            _LeafGradeRow(
              leafId: question.id,
              maxPoints: question.points,
              grade: _gradeFor(question.id),
              editable: editing,
              onChanged: (s, c) => _setGrade(question.id, s, c, question.points),
            )
          else
            ...question.subQuestions.map((sub) => _LeafGradeRow(
                  key: ValueKey(sub.id),
                  leafId: sub.id,
                  label: sub.label,
                  statement: sub.statement,
                  maxPoints: sub.points,
                  grade: _gradeFor(sub.id),
                  editable: editing,
                  onChanged: (s, c) => _setGrade(sub.id, s, c, sub.points),
                )),
        ],
      ),
    );
  }

  double _totalScore() {
    if (question.isLeaf) return _gradeFor(question.id).score;
    return question.subQuestions
        .fold<double>(0, (s, sub) => s + _gradeFor(sub.id).score);
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

class _LeafGradeRow extends StatefulWidget {
  final String leafId;
  final String? label;
  final String? statement;
  final double maxPoints;
  final QuestionGrade grade;
  final bool editable;
  final void Function(double score, String comment) onChanged;

  const _LeafGradeRow({
    super.key,
    required this.leafId,
    this.label,
    this.statement,
    required this.maxPoints,
    required this.grade,
    required this.editable,
    required this.onChanged,
  });

  @override
  State<_LeafGradeRow> createState() => _LeafGradeRowState();
}

class _LeafGradeRowState extends State<_LeafGradeRow> {
  late final TextEditingController _scoreCtrl =
      TextEditingController(text: _fmt(widget.grade.score));
  late final TextEditingController _commentCtrl =
      TextEditingController(text: widget.grade.comment);

  @override
  void dispose() {
    _scoreCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasLabel = widget.label != null;
    return Container(
      margin: EdgeInsets.only(top: hasLabel ? 8 : 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (hasLabel) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    widget.label!,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  widget.statement?.isNotEmpty == true
                      ? widget.statement!
                      : (hasLabel ? '' : '—'),
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(width: 6),
              if (widget.editable)
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _scoreCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.surfaceMuted,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      suffixText: '/${_fmt(widget.maxPoints)}',
                      suffixStyle: const TextStyle(fontSize: 11),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      final n =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      widget.onChanged(n, _commentCtrl.text);
                    },
                  ),
                )
              else
                Text(
                  '${_fmt(widget.grade.score)}/${_fmt(widget.maxPoints)}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (widget.editable)
            TextField(
              controller: _commentCtrl,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceMuted,
                hintText: 'Commentaire',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(14)),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) {
                widget.onChanged(
                  double.tryParse(
                          _scoreCtrl.text.replaceAll(',', '.')) ??
                      0,
                  v,
                );
              },
            )
          else if (widget.grade.comment.isNotEmpty)
            // Détection zone illisible : badge orange avec icône + commentaire
            widget.grade.comment.startsWith('[ZONE_ILLISIBLE]')
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.warning,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.visibility_off_outlined,
                            color: AppColors.warning,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'ZONE ILLISIBLE',
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.grade.comment
                                      .replaceFirst(
                                        RegExp(
                                            r'^\[ZONE_ILLISIBLE\][\s:]*'),
                                        '',
                                      )
                                      .trim(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Activez le mode édition (✎) en haut pour saisir le sens et noter cette question.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      widget.grade.comment,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

/// Bandeau cliquable affiché en haut quand une copie a des zones illisibles.
/// Tap → ouvre l'écran HIL pour les corriger en lot.
class _IllegibleZonesBanner extends StatelessWidget {
  final int count;
  final VoidCallback onResolve;

  const _IllegibleZonesBanner({
    required this.count,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onResolve,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.10),
            border: Border.all(color: AppColors.warning, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count ZONE${count > 1 ? 'S' : ''} ILLISIBLE${count > 1 ? 'S' : ''}',
                      style: const TextStyle(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'L\'IA n\'a pas pu lire certaines réponses. '
                      'Aidez-la en saisissant le texte manquant.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.warning,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
