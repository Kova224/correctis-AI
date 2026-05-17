import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import '../../widgets/status_chip.dart';

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
            actions: copy.status == CopyStatus.graded
                ? [
                    IconButton(
                      icon: Icon(_editing ? Icons.check : Icons.edit_outlined,
                          color: Colors.white),
                      onPressed: () => setState(() => _editing = !_editing),
                    ),
                  ]
                : null,
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
                    child: Row(
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
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (copy.pageImages.isNotEmpty) ...[
                  Text(
                    'Pages scannées',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
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
                        final file = File(path);
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 130,
                            color: AppColors.surfaceMuted,
                            child: file.existsSync()
                                ? Image.file(file, fit: BoxFit.cover)
                                : const Center(
                                    child: Icon(Icons.image,
                                        color: AppColors.textMuted)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                if (copy.status == CopyStatus.graded) ...[
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
                          'Lancez la correction maintenant.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        PrimaryButton(
                          label: 'Lancer la correction',
                          icon: Icons.auto_awesome,
                          onPressed: () => context
                              .read<ExamService>()
                              .startCorrection(copy.id),
                        ),
                      ],
                    ),
                  ),
                ] else if (copy.status == CopyStatus.error)
                  SectionCard(
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.danger, size: 36),
                        const SizedBox(height: 8),
                        const Text('Erreur de correction',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => context
                              .read<ExamService>()
                              .startCorrection(copy.id),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
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
            Padding(
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
