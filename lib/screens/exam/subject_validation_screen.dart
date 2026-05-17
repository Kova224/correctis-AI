import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/question.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import 'correction_source_screen.dart';
import 'manual_subject_entry_screen.dart';

/// Étape 3 — validation et édition de la structure complète :
/// énoncé, exercices, sous-questions, barèmes.
class SubjectValidationScreen extends StatefulWidget {
  final String examId;
  const SubjectValidationScreen({super.key, required this.examId});

  @override
  State<SubjectValidationScreen> createState() =>
      _SubjectValidationScreenState();
}

class _SubjectValidationScreenState extends State<SubjectValidationScreen> {
  late List<Question> _questions;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final exam = context.read<ExamService>().getExam(widget.examId);
    _questions = exam == null
        ? <Question>[]
        : exam.questions.map((q) => _deepCopy(q)).toList();
  }

  Question _deepCopy(Question q) => Question(
        id: q.id,
        label: q.label,
        statement: q.statement,
        points: q.points,
        subQuestions: q.subQuestions
            .map((s) => SubQuestion(
                  id: s.id,
                  label: s.label,
                  statement: s.statement,
                  points: s.points,
                ))
            .toList(),
      );

  double get _total =>
      _questions.fold<double>(0, (sum, q) => sum + q.totalPoints);

  void _addExercise() {
    setState(() {
      _questions.add(Question(
        label: 'Exercice ${_questions.length + 1}',
        statement: '',
        subQuestions: [
          SubQuestion(label: 'a)', statement: '', points: 2),
        ],
      ));
    });
  }

  void _addSimpleQuestion() {
    setState(() {
      _questions.add(Question(
        label: 'Question ${_questions.length + 1}',
        statement: '',
        points: 2,
      ));
    });
  }

  void _removeQuestion(int index) {
    setState(() => _questions.removeAt(index));
  }

  void _moveQuestion(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = _questions.removeAt(oldIndex);
      _questions.insert(newIndex, item);
    });
  }

  void _addSubQuestion(int qIndex) {
    setState(() {
      final q = _questions[qIndex];
      final nextLetter =
          String.fromCharCode('a'.codeUnitAt(0) + q.subQuestions.length);
      q.subQuestions.add(SubQuestion(
        label: '$nextLetter)',
        statement: '',
        points: 1,
      ));
      // si la question avait des points en mode "feuille", on les remet à 0
      q.points = 0;
    });
  }

  void _removeSubQuestion(int qIndex, int subIndex) {
    setState(() {
      _questions[qIndex].subQuestions.removeAt(subIndex);
    });
  }

  Future<void> _openManualEntry() async {
    final result = await Navigator.of(context).push<List<Question>>(
      MaterialPageRoute(
        builder: (_) => ManualSubjectEntryScreen(initial: _questions),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _questions
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _validate() async {
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoutez au moins une question ou un exercice.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final exam = context.read<ExamService>().getExam(widget.examId)!;
      exam.questions
        ..clear()
        ..addAll(_questions);
      exam.subjectValidated = true;
      exam.totalPoints = _total;
      await context.read<ExamService>().updateExam(exam);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => CorrectionSourceScreen(examId: widget.examId),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RoundedHeader(
            height: 200,
            showBackButton: true,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fact_check_outlined,
                      color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'VALIDATION DU SUJET',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vérifier ou compléter — énoncé, sous-questions, barème',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                // Carte total + bouton saisie manuelle
                SectionCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.calculate,
                                color: AppColors.accentDark),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    )),
                                Text(
                                  '${_fmt(_total)} pts',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _openManualEntry,
                        icon: const Icon(Icons.edit_note),
                        label: const Text(
                            'Saisie manuelle (recopier le sujet exact)'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Aide explicative
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Recopiez chaque exercice et chaque sous-question avec son barème exact, comme sur le sujet.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppColors.primary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_questions.isEmpty)
                  SectionCard(
                    child: Column(
                      children: [
                        const Icon(Icons.help_outline,
                            size: 40, color: AppColors.textMuted),
                        const SizedBox(height: 8),
                        const Text('Aucun exercice détecté',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          'Ajoutez les exercices ou questions manuellement avec les boutons ci-dessous.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: _questions.length,
                    onReorder: _moveQuestion,
                    itemBuilder: (context, i) {
                      final q = _questions[i];
                      return Padding(
                        key: ValueKey(q.id),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ExerciseCard(
                          question: q,
                          index: i,
                          onChanged: () => setState(() {}),
                          onRemove: () => _removeQuestion(i),
                          onAddSub: () => _addSubQuestion(i),
                          onRemoveSub: (subIdx) => _removeSubQuestion(i, subIdx),
                        ),
                      );
                    },
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addExercise,
                        icon: const Icon(Icons.add_box_outlined),
                        label: const Text('Exercice'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addSimpleQuestion,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text('Question'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Valider le sujet',
                  icon: Icons.check,
                  loading: _saving,
                  onPressed: _validate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

// =============================================================================
// CARTE EXERCICE / QUESTION
// =============================================================================
class _ExerciseCard extends StatefulWidget {
  final Question question;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback onAddSub;
  final ValueChanged<int> onRemoveSub;

  const _ExerciseCard({
    required this.question,
    required this.index,
    required this.onChanged,
    required this.onRemove,
    required this.onAddSub,
    required this.onRemoveSub,
  });

  @override
  State<_ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<_ExerciseCard> {
  late final TextEditingController _label =
      TextEditingController(text: widget.question.label);
  late final TextEditingController _statement =
      TextEditingController(text: widget.question.statement);
  late final TextEditingController _points = TextEditingController(
      text: _fmt(widget.question.points));

  @override
  void dispose() {
    _label.dispose();
    _statement.dispose();
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header avec drag, label + total, supprimer
          Row(
            children: [
              ReorderableDragStartListener(
                index: widget.index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.drag_indicator,
                      color: AppColors.textMuted),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Exercice 1, Question 1, …',
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: AppColors.primary, width: 1),
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: (v) {
                    q.label = v;
                    widget.onChanged();
                  },
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${_fmt(q.totalPoints)} pts',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Énoncé
          TextField(
            controller: _statement,
            maxLines: null,
            minLines: 2,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: const InputDecoration(
              hintText:
                  'Énoncé complet de l\'exercice — copier exactement le sujet (équations, symboles, données…)',
              filled: true,
              fillColor: AppColors.surfaceMuted,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: (v) {
              q.statement = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 12),
          // Mode feuille (pas de sub) → champ points direct
          if (q.isLeaf) ...[
            Row(
              children: [
                const Icon(Icons.star_outline,
                    size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                const Text('Note :',
                    style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _points,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: AppColors.surfaceMuted,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(20)),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.all(Radius.circular(20)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) {
                      q.points =
                          double.tryParse(v.replaceAll(',', '.')) ?? 0;
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: widget.onAddSub,
                  icon: const Icon(Icons.subdirectory_arrow_right, size: 16),
                  label: const Text('Ajouter sous-questions'),
                ),
              ],
            ),
          ] else ...[
            // Sous-questions
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 4),
              child: Column(
                children: List.generate(q.subQuestions.length, (i) {
                  final sub = q.subQuestions[i];
                  return _SubQuestionEditor(
                    key: ValueKey(sub.id),
                    sub: sub,
                    onChanged: widget.onChanged,
                    onRemove: () => widget.onRemoveSub(i),
                  );
                }),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: widget.onAddSub,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Ajouter une sous-question'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// ÉDITEUR DE SOUS-QUESTION
// =============================================================================
class _SubQuestionEditor extends StatefulWidget {
  final SubQuestion sub;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _SubQuestionEditor({
    super.key,
    required this.sub,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_SubQuestionEditor> createState() => _SubQuestionEditorState();
}

class _SubQuestionEditorState extends State<_SubQuestionEditor> {
  late final TextEditingController _label =
      TextEditingController(text: widget.sub.label);
  late final TextEditingController _statement =
      TextEditingController(text: widget.sub.statement);
  late final TextEditingController _points =
      TextEditingController(text: _fmt(widget.sub.points));

  @override
  void dispose() {
    _label.dispose();
    _statement.dispose();
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, color: AppColors.primary),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.pill)),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.all(Radius.circular(AppRadius.pill)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    widget.sub.label = v;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _statement,
                  maxLines: null,
                  minLines: 1,
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Énoncé de la sous-question…',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    widget.sub.statement = v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 4),
              const Icon(Icons.star_outline,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              const Text('pts :',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 6),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _points,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 13.5),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) {
                    widget.sub.points =
                        double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    widget.onChanged();
                  },
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close,
                    size: 18, color: AppColors.danger),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
