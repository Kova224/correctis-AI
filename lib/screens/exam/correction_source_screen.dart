import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/correction_source.dart';
import '../../services/ai_correction_service.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import 'exam_detail_screen.dart';

class CorrectionSourceScreen extends StatefulWidget {
  final String examId;
  const CorrectionSourceScreen({super.key, required this.examId});

  @override
  State<CorrectionSourceScreen> createState() => _CorrectionSourceScreenState();
}

class _CorrectionSourceScreenState extends State<CorrectionSourceScreen> {
  CorrectionSourceType _selected = CorrectionSourceType.answerKey;
  final List<String> _docs = <String>[];
  final TextEditingController _generatedCtrl = TextEditingController();
  bool _generating = false;
  bool _saving = false;
  bool _aiValidated = false;

  @override
  void dispose() {
    _generatedCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDoc() async {
    final XFile? f =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) setState(() => _docs.add(f.path));
  }

  Future<void> _pickFromCamera() async {
    final XFile? f =
        await ImagePicker().pickImage(source: ImageSource.camera);
    if (f != null) setState(() => _docs.add(f.path));
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final exam = context.read<ExamService>().getExam(widget.examId)!;
      final text = await AiCorrectionService().generateAnswerKey(exam);
      _generatedCtrl.text = text;
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _save() async {
    if (_selected == CorrectionSourceType.answerKey && _docs.isEmpty) {
      _snack('Ajoutez au moins un document de corrigé.');
      return;
    }
    if (_selected == CorrectionSourceType.course && _docs.isEmpty) {
      _snack('Ajoutez votre cours / support.');
      return;
    }
    if (_selected == CorrectionSourceType.aiGenerated) {
      if (_generatedCtrl.text.trim().isEmpty) {
        _snack('Générez d\'abord un corrigé.');
        return;
      }
      if (!_aiValidated) {
        _snack(
            'Validez le corrigé IA en cochant la case avant de continuer.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final exam = context.read<ExamService>().getExam(widget.examId)!;
      exam.correctionSource = CorrectionSource(
        type: _selected,
        documentPaths: _selected == CorrectionSourceType.aiGenerated
            ? const []
            : List.of(_docs),
        generatedContent: _selected == CorrectionSourceType.aiGenerated
            ? _generatedCtrl.text
            : null,
        validated: _selected == CorrectionSourceType.aiGenerated
            ? _aiValidated
            : true,
      );
      await context.read<ExamService>().updateExam(exam);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ExamDetailScreen(examId: widget.examId),
        ),
        (route) => route.isFirst,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

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
                  const Icon(Icons.school_outlined,
                      color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'SOURCE DE CORRECTION',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choisissez UN seul mode',
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
                ...CorrectionSourceType.values.map((type) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _SourceOption(
                      type: type,
                      selected: _selected == type,
                      onTap: () => setState(() => _selected = type),
                    ),
                  );
                }),
                const SizedBox(height: 16),
                _detailForSelected(),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Valider la source',
                  icon: Icons.check_circle_outline,
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailForSelected() {
    switch (_selected) {
      case CorrectionSourceType.answerKey:
      case CorrectionSourceType.course:
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selected == CorrectionSourceType.answerKey
                    ? 'Documents du corrigé type'
                    : 'Cours / Support de référence',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _selected == CorrectionSourceType.answerKey
                    ? 'Vous pouvez mélanger photos / images / PDF — l\'IA les utilisera comme référence unique.'
                    : 'L\'IA évaluera les copies en fonction de votre cours.',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromCamera,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: const Text('Photo'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDoc,
                      icon: const Icon(Icons.attach_file),
                      label: const Text('Fichier'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_docs.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Text(
                    'Aucun document ajouté',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_docs.length, (i) {
                    return Chip(
                      avatar: const Icon(Icons.description,
                          size: 16, color: AppColors.primary),
                      label: Text('Doc ${i + 1}'),
                      onDeleted: () => setState(() => _docs.removeAt(i)),
                    );
                  }),
                ),
            ],
          ),
        );
      case CorrectionSourceType.aiGenerated:
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Corrigé généré par l\'IA',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'L\'IA propose un corrigé basé sur le sujet validé. Modifiez-le si besoin, puis cochez "Je valide" pour l\'utiliser.',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                    _generating ? 'Génération...' : 'Générer le corrigé'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _generatedCtrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Le corrigé généré apparaîtra ici…',
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: _aiValidated,
                onChanged: (v) =>
                    setState(() => _aiValidated = v ?? false),
                title: const Text(
                  'Je valide ce corrigé',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                    'Aucune correction n\'est possible sans validation.'),
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ],
          ),
        );
    }
  }
}

class _SourceOption extends StatelessWidget {
  final CorrectionSourceType type;
  final bool selected;
  final VoidCallback onTap;
  const _SourceOption({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.divider;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: color, width: selected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_iconFor(type), color: AppColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    type.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    type.subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.divider,
                  width: 2,
                ),
                color: selected ? AppColors.primary : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(CorrectionSourceType t) {
    switch (t) {
      case CorrectionSourceType.answerKey:
        return Icons.fact_check_outlined;
      case CorrectionSourceType.course:
        return Icons.menu_book_outlined;
      case CorrectionSourceType.aiGenerated:
        return Icons.auto_awesome;
    }
  }
}
