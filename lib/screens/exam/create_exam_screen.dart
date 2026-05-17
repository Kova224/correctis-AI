import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/exam.dart';
import '../../services/auth_service.dart';
import '../../services/exam_service.dart';
import '../../services/ocr_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import 'exam_detail_screen.dart';
import 'subject_validation_screen.dart';

/// Étape 1 — saisie des infos générales (titre, classe, note totale).
class CreateExamScreen extends StatefulWidget {
  const CreateExamScreen({super.key});

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _className = TextEditingController();
  final _total = TextEditingController(text: '20');
  ExamLanguage _language = ExamLanguage.french;
  ExamType _examType = ExamType.general;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _className.dispose();
    _total.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final user = context.read<AuthService>().currentUser!;
      final exam = await context.read<ExamService>().createExam(
            ownerId: user.id,
            title: _title.text.trim(),
            className: _className.text.trim().isEmpty
                ? null
                : _className.text.trim(),
            totalPoints: double.tryParse(_total.text.replaceAll(',', '.')) ?? 20,
            language: _language,
            examType: _examType,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ImportSubjectScreen(examId: exam.id)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoundedHeader(
            height: 200,
            showBackButton: true,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.create_new_folder_outlined,
                      color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'NOUVEL EXAMEN',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Étape 1 sur 3 — Informations générales',
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
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Informations',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 16),
                        CustomTextField(
                          label: 'Titre de l\'examen *',
                          hint: 'Ex : Devoir de mathématiques – Chapitre 3',
                          controller: _title,
                          textInputAction: TextInputAction.next,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Titre requis'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        CustomTextField(
                          label: 'Classe (optionnel)',
                          hint: 'Ex : 3ème B',
                          controller: _className,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 14),
                        CustomTextField(
                          label: 'Note totale (sur)',
                          hint: '20',
                          controller: _total,
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n =
                                double.tryParse((v ?? '').replaceAll(',', '.'));
                            if (n == null || n <= 0) return 'Valeur invalide';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'La note totale sera recalculée automatiquement selon la somme des points par question, mais vous pourrez la fixer.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sélecteur Langue
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.language, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Langue de l\'examen',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ExamLanguage.values.map((lang) {
                            final selected = _language == lang;
                            return _OptionPill(
                              label: '${lang.flag}  ${lang.label}',
                              selected: selected,
                              onTap: () =>
                                  setState(() => _language = lang),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Sélecteur Type d'examen
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.category_outlined,
                                color: AppColors.primary),
                            const SizedBox(width: 10),
                            Text(
                              'Type d\'examen',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Aide l\'IA à mieux extraire et comprendre les questions.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ExamType.values.map((t) {
                            final selected = _examType == t;
                            return _OptionPill(
                              label: '${t.emoji}  ${t.label}',
                              selected: selected,
                              onTap: () =>
                                  setState(() => _examType = t),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    label: 'Continuer',
                    icon: Icons.arrow_forward,
                    loading: _saving,
                    onPressed: _continue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Étape 2 — import du sujet (caméra ou galerie).
class ImportSubjectScreen extends StatefulWidget {
  final String examId;
  const ImportSubjectScreen({super.key, required this.examId});

  @override
  State<ImportSubjectScreen> createState() => _ImportSubjectScreenState();
}

class _ImportSubjectScreenState extends State<ImportSubjectScreen> {
  final _picker = ImagePicker();
  final List<String> _pages = <String>[];
  bool _analyzing = false;

  Exam get _exam => context.read<ExamService>().getExam(widget.examId)!;

  Future<void> _addFromCamera() async {
    final XFile? f = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
    );
    if (f != null) setState(() => _pages.add(f.path));
  }

  Future<void> _addFromGallery() async {
    final List<XFile> files = await _picker.pickMultiImage(imageQuality: 75);
    if (files.isNotEmpty) {
      setState(() => _pages.addAll(files.map((f) => f.path)));
    }
  }

  Future<void> _continue() async {
    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez importer au moins une page du sujet.'),
        ),
      );
      return;
    }
    setState(() => _analyzing = true);
    try {
      // OCR + IA → liste de questions / barème (adaptée à la langue & au type)
      final ocr = OcrService();
      final exam = _exam;
      final questions = await ocr.extractQuestionsFromSubject(
        _pages,
        language: exam.language,
        examType: exam.examType,
      );
      exam.subjectImages.addAll(_pages);
      exam.questions.addAll(questions);
      await context.read<ExamService>().updateExam(exam);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SubjectValidationScreen(examId: widget.examId),
        ),
      );
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RoundedHeader(
            height: 200,
            showBackButton: true,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.document_scanner_outlined,
                      color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  Text(
                    'IMPORT DU SUJET',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Étape 2 sur 3 — Photo ou fichier image',
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
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sources',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ImportTile(
                              icon: Icons.camera_alt_outlined,
                              label: 'Caméra',
                              onTap: _addFromCamera,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ImportTile(
                              icon: Icons.image_outlined,
                              label: 'Galerie',
                              onTap: _addFromGallery,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_pages.isEmpty)
                  _emptyHint()
                else
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pages importées (${_pages.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _pages.length,
                          itemBuilder: (context, i) => _Thumbnail(
                            path: _pages[i],
                            index: i + 1,
                            onRemove: () =>
                                setState(() => _pages.removeAt(i)),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 28),
                if (_analyzing) _AnalyzingCard(pageCount: _pages.length),
                if (_analyzing) const SizedBox(height: 16),
                PrimaryButton(
                  label: _analyzing
                      ? 'Analyse en cours...'
                      : 'Analyser et extraire les questions',
                  icon: Icons.auto_awesome,
                  loading: _analyzing,
                  onPressed: _continue,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyHint() {
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.info_outline, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Aucune page importée. Ajoutez le sujet de l\'examen — l\'IA extraira les questions et le barème.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImportTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ImportTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final String path;
  final int index;
  final VoidCallback onRemove;
  const _Thumbnail({
    required this.path,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.expand(
            child: _SafeFileImage(path: path),
          ),
        ),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              'Page $index',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _SafeFileImage extends StatelessWidget {
  final String path;
  const _SafeFileImage({required this.path});

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (!file.existsSync()) {
      return Container(
        color: AppColors.surfaceMuted,
        child: const Center(
          child: Icon(Icons.image, color: AppColors.textMuted, size: 32),
        ),
      );
    }
    return Image.file(file, fit: BoxFit.cover);
  }
}

class _AnalyzingCard extends StatefulWidget {
  final int pageCount;
  const _AnalyzingCard({required this.pageCount});

  @override
  State<_AnalyzingCard> createState() => _AnalyzingCardState();
}

class _AnalyzingCardState extends State<_AnalyzingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _step = 0;
  static const _steps = [
    'Lecture des pages (OCR)…',
    'Extraction des questions…',
    'Détection du barème…',
    'Mise en forme finale…',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _tickStep();
  }

  Future<void> _tickStep() async {
    final stepDelay = Duration(milliseconds: 700 + 400 * widget.pageCount);
    while (mounted && _step < _steps.length - 1) {
      await Future.delayed(stepDelay);
      if (mounted) setState(() => _step++);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: RotationTransition(
                  turns: _ctrl,
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.primary, size: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Analyse intelligente en cours',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_steps.length, (i) {
            final isDone = i < _step;
            final isCurrent = i == _step;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    isDone
                        ? Icons.check_circle
                        : (isCurrent
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked),
                    size: 18,
                    color: isDone
                        ? AppColors.success
                        : (isCurrent
                            ? AppColors.primary
                            : AppColors.textMuted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: TextStyle(
                        color: isDone || isCurrent
                            ? AppColors.textPrimary
                            : AppColors.textMuted,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _OptionPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _OptionPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: selected ? AppColors.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
