import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/exam.dart';
import '../../services/auth_service.dart';
import '../../services/establishment_service.dart';
import '../../services/exam_service.dart';
import '../../services/ocr_service.dart';
import '../../theme/app_theme.dart';
import 'subject_validation_screen.dart';

/// Écran "Créer un examen" — V2 selon maquette P2.
///
/// Layout :
///   [← Back] CRÉER UN EXAMEN
///   [Titre] [Classe] [Date]
///   [Type d'examen + Langue]  (pills sélectionnables)
///   [→ Bouton continuer vers import du sujet]
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
  ControlType _controlType = ControlType.general;
  String? _establishmentId; // si prof rattaché à une école
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Préselectionne l'école active si l'user est membre d'une école.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final estab = context.read<EstablishmentService>();
      if (estab.hasEstablishment) {
        setState(() => _establishmentId =
            estab.currentEstablishment!.id);
      }
    });
  }

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
            totalPoints:
                double.tryParse(_total.text.replaceAll(',', '.')) ?? 20,
            language: _language,
            examType: _examType,
            controlType: _controlType,
            establishmentId: _establishmentId,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => ImportSubjectScreen(examId: exam.id)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 1.4,
            colors: [Color(0xFF0A1F3E), AppColors.voidBg],
            stops: [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // ───── Header back + titre
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      _BackButton(onTap: () => Navigator.maybePop(context)),
                      const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '← MES EXAMENS',
                        style: AppFonts.mono(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Créer un examen',
                        style: AppFonts.fraunces(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sujet · Barème · Source de correction',
                        style: AppFonts.sans(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ───── Champs
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: [
                      // TITRE
                      _FieldCard(
                        label: 'TITRE',
                        child: TextFormField(
                          controller: _title,
                          textInputAction: TextInputAction.next,
                          style: AppFonts.sans(fontSize: 14),
                          decoration: _fieldInputDecoration(
                              hint: 'Ex : Contrôle Maths — 3ème A'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Titre requis'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 9),

                      // CLASSE + NOTE
                      Row(
                        children: [
                          Expanded(
                            child: _FieldCard(
                              label: 'CLASSE',
                              child: TextFormField(
                                controller: _className,
                                textInputAction: TextInputAction.next,
                                style: AppFonts.sans(fontSize: 14),
                                decoration: _fieldInputDecoration(
                                    hint: '3ème A'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: _FieldCard(
                              label: 'NOTÉ /',
                              child: TextFormField(
                                controller: _total,
                                keyboardType: TextInputType.number,
                                style: AppFonts.sans(fontSize: 14),
                                decoration:
                                    _fieldInputDecoration(hint: '20'),
                                validator: (v) {
                                  final n = double.tryParse(
                                      (v ?? '').replaceAll(',', '.'));
                                  if (n == null || n <= 0) return '?';
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // ─── ÉCOLE DE RATTACHEMENT (Michel — remis) ───
                      // Le prof choisit EXPLICITEMENT à quelle école cet
                      // examen est destiné. Solo = examen personnel qui
                      // n'apparaîtra dans AUCUN casier école.
                      Consumer<EstablishmentService>(
                        builder: (context, estab, _) {
                          final memberships = estab.myMemberships
                              .where((m) => m.isActive)
                              .toList();
                          if (memberships.isEmpty) {
                            // Prof solo : pas de choix, l'examen reste perso
                            return const SizedBox.shrink();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CET EXAMEN EST POUR',
                                style: AppFonts.mono(
                                  fontSize: 9,
                                  color: AppColors.primaryLight,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Le choix est définitif — les notes iront '
                                'uniquement dans le casier de cette école.',
                                style: AppFonts.sans(
                                  fontSize: 10.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _OptionPill(
                                    label: '👤  Personnel (solo)',
                                    selected: _establishmentId == null,
                                    onTap: () => setState(
                                        () => _establishmentId = null),
                                  ),
                                  ...memberships.map((m) => _OptionPill(
                                        label:
                                            '🏛️  ${m.establishmentName}',
                                        selected: _establishmentId ==
                                            m.establishmentId,
                                        onTap: () => setState(() =>
                                            _establishmentId =
                                                m.establishmentId),
                                      )),
                                ],
                              ),
                              const SizedBox(height: 18),
                            ],
                          );
                        },
                      ),

                      // TYPE D'EXAMEN
                      // Michel : filtre par les matières attribuées dans
                      // l'école SÉLECTIONNÉE ci-dessus (pas la courante).
                      // Solo → toutes matières dispo.
                      Consumer<EstablishmentService>(
                        builder: (context, estab, _) {
                          List<String> assigned = const [];
                          if (_establishmentId != null) {
                            final m = estab.myMemberships.where(
                              (mm) => mm.establishmentId == _establishmentId,
                            );
                            if (m.isNotEmpty) {
                              assigned = m.first.matieres;
                            }
                          }
                          final availableTypes = assigned.isEmpty
                              ? ExamType.values
                              : ExamType.values
                                  .where((t) => assigned.contains(t.code))
                                  .toList();
                          // Si la matière courante n'est plus dans les
                          // dispo, on la réinitialise à la première dispo.
                          if (availableTypes.isNotEmpty &&
                              !availableTypes.contains(_examType)) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() =>
                                    _examType = availableTypes.first);
                              }
                            });
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TYPE D\'EXAMEN',
                                style: AppFonts.mono(
                                  fontSize: 9,
                                  color: AppColors.primaryLight,
                                  letterSpacing: 2,
                                ),
                              ),
                              if (assigned.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Matières attribuées par l\'admin',
                                  style: AppFonts.sans(
                                    fontSize: 10.5,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if (availableTypes.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning
                                        .withValues(alpha: 0.10),
                                    border: Border.all(
                                      color: AppColors.warning
                                          .withValues(alpha: 0.30),
                                    ),
                                    borderRadius: BorderRadius.circular(
                                        AppRadius.md),
                                  ),
                                  child: Text(
                                    'Aucune matière ne vous a été attribuée par '
                                    'l\'admin de cette école. Contactez-le pour '
                                    'qu\'il vous en attribue.',
                                    style: AppFonts.sans(
                                      fontSize: 11.5,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: availableTypes.map((t) {
                                    return _OptionPill(
                                      label: '${t.emoji}  ${t.label}',
                                      selected: _examType == t,
                                      onTap: () =>
                                          setState(() => _examType = t),
                                    );
                                  }).toList(),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 18),

                      // LANGUE
                      Text(
                        'LANGUE',
                        style: AppFonts.mono(
                          fontSize: 9,
                          color: AppColors.primaryLight,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: ExamLanguage.values.map((lang) {
                          return _OptionPill(
                            label: '${lang.flag}  ${lang.label}',
                            selected: _language == lang,
                            onTap: () => setState(() => _language = lang),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),

                      // NOTE : "Type de contrôle" et "École de rattachement"
                      // ont été retirés (retour Michel — simplification UX).
                      // Le type reste géré côté DB (default ControlType.general).
                      // L'établissement sera auto-détecté depuis le contexte
                      // école active du prof (feature multi-écoles à venir).

                      // BADGE IA
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.profPrimary.withValues(alpha: 0.07),
                          border: Border.all(
                              color: AppColors.profPrimary
                                  .withValues(alpha: 0.2)),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.profPrimary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.profPrimary,
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'L\'IA extraira les questions et le barème au prochain écran',
                                style: AppFonts.sans(
                                  fontSize: 11,
                                  color: AppColors.profPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ───── Bouton continuer (gradient vert maquette)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: _GradientNextButton(
                    label: 'CRÉER L\'EXAMEN →',
                    loading: _saving,
                    onTap: _continue,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldInputDecoration({String? hint}) {
    return InputDecoration(
      filled: false,
      contentPadding: EdgeInsets.zero,
      hintText: hint,
      hintStyle: AppFonts.sans(fontSize: 14, color: AppColors.textMuted),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      isDense: true,
      errorStyle: const TextStyle(fontSize: 0, height: 0),
    );
  }
}

// =============================================================================
// ÉCRAN 2 — IMPORT DU SUJET (style maquette P2 upload zone)
// =============================================================================

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
      final ocr = OcrService();
      final exam = _exam;
      final result = await ocr.extractQuestionsFromSubject(
        _pages,
        language: exam.language,
        examType: exam.examType,
      );
      exam.subjectImages.addAll(result.uploadedUrls);
      exam.questions.addAll(result.questions);
      await context.read<ExamService>().updateExam(exam);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SubjectValidationScreen(examId: widget.examId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Extraction du sujet impossible'),
          content: SingleChildScrollView(
            child: Text(
              '$e\n\nVérifiez :\n'
              '• Votre connexion internet\n'
              '• Que les photos du sujet sont nettes et lisibles\n'
              '• Que les Edge Functions Supabase sont déployées',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 1.4,
            colors: [Color(0xFF0A1F3E), AppColors.voidBg],
            stops: [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    _BackButton(onTap: () => Navigator.maybePop(context)),
                    const Spacer(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '← INFOS EXAMEN',
                      style: AppFonts.mono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Importer le sujet',
                      style: AppFonts.fraunces(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Photographiez ou importez les pages',
                      style: AppFonts.sans(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    // UPLOAD ZONE — style maquette dashed blue
                    _UploadZone(
                      onCamera: _addFromCamera,
                      onGallery: _addFromGallery,
                    ),
                    const SizedBox(height: 14),
                    // Badge IA
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            AppColors.profPrimary.withValues(alpha: 0.07),
                        border: Border.all(
                            color: AppColors.profPrimary
                                .withValues(alpha: 0.2)),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.profPrimary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.profPrimary,
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'IA extrait questions + barème automatiquement',
                              style: AppFonts.sans(
                                fontSize: 11,
                                color: AppColors.profPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Pages importées
                    if (_pages.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text(
                        'PAGES IMPORTÉES (${_pages.length})',
                        style: AppFonts.mono(
                          fontSize: 9,
                          color: AppColors.textMuted,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.75,
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

                    if (_analyzing) ...[
                      const SizedBox(height: 22),
                      _AnalyzingCard(pageCount: _pages.length),
                    ],
                  ],
                ),
              ),

              // Bouton analyser (gradient vert)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: _GradientNextButton(
                  label: _analyzing
                      ? 'ANALYSE EN COURS…'
                      : 'ANALYSER LE SUJET →',
                  loading: _analyzing,
                  onTap: _continue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// COMPOSANTS RÉUTILISABLES (style maquette)
// ─────────────────────────────────────────────────────────────────────────

/// Bouton retour circulaire — style maquette (card + bordure subtile).
class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 14,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Carte de champ — label DM Mono bleu + input.
class _FieldCard extends StatelessWidget {
  final String label;
  final Widget child;
  const _FieldCard({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      decoration: BoxDecoration(
        color: const Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppFonts.mono(
              fontSize: 9,
              color: AppColors.primaryLight,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// Pill sélectionnable — style maquette (vert quand actif).
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
    return Material(
      color: selected
          ? AppColors.profPrimary.withValues(alpha: 0.1)
          : const Color(0x0AFFFFFF),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? AppColors.profPrimary.withValues(alpha: 0.4)
                  : AppColors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            label,
            style: AppFonts.sans(
              fontSize: 12,
              color:
                  selected ? AppColors.profPrimary : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton "Continuer" en dégradé vert pleine largeur — style maquette.
class _GradientNextButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _GradientNextButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.profGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.profPrimary.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      label,
                      style: AppFonts.mono(
                        fontSize: 12,
                        color: Colors.white,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Zone d'upload — dashed bleu maquette P2.
class _UploadZone extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  const _UploadZone({required this.onCamera, required this.onGallery});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
          width: 1.5,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.upload_file_outlined,
              size: 32, color: AppColors.primaryLight),
          const SizedBox(height: 10),
          Text(
            'Importer le sujet',
            style: AppFonts.sans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'PDF · JPG · PNG',
            style: AppFonts.mono(
              fontSize: 10,
              letterSpacing: 1.5,
              color: AppColors.primaryLight,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _UploadButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'CAMÉRA',
                  onTap: onCamera,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _UploadButton(
                  icon: Icons.image_outlined,
                  label: 'GALERIE',
                  onTap: onGallery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UploadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _UploadButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.primaryLight),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppFonts.mono(
                  fontSize: 9,
                  letterSpacing: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vignette d'une page importée — petite avec badge index et bouton remove.
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        color: AppColors.primary.withValues(alpha: 0.08),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox.expand(child: _SafeFileImage(path: path)),
          ),
          // Badge OK vert
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: AppColors.profPrimary,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.check, size: 10, color: Colors.white),
              ),
            ),
          ),
          // Badge index
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '$index',
                style: AppFonts.mono(
                  fontSize: 9,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
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
        color: AppColors.card2,
        child: const Center(
          child: Icon(Icons.image, color: AppColors.textMuted, size: 20),
        ),
      );
    }
    return Image.file(file, fit: BoxFit.cover);
  }
}

/// Card d'analyse en cours — style maquette IA (orbe + steps).
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
    'OCR manuscrit (TrOCR)',
    'Extraction des questions',
    'Détection du barème',
    'Validation finale',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RotationTransition(
                turns: _ctrl,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: [
                        Color(0xFF059669),
                        Color(0xFF0D9488),
                        Color(0xFF2DD4BF),
                        Color(0xFF3B82F6),
                        Color(0xFF059669),
                      ],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Analyse IA en cours…',
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(_steps.length, (i) {
            final isDone = i < _step;
            final isCurrent = i == _step;
            final color = isDone
                ? AppColors.profPrimary
                : isCurrent
                    ? AppColors.primaryLight
                    : AppColors.textMuted;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone || isCurrent
                          ? color.withValues(alpha: 0.15)
                          : Colors.transparent,
                      border: Border.all(color: color, width: 1.5),
                    ),
                    child: isDone
                        ? const Center(
                            child: Icon(Icons.check,
                                size: 8, color: AppColors.profPrimary))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _steps[i],
                    style: AppFonts.sans(
                      fontSize: 11,
                      color: color,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.w400,
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
