import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../models/exam.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';

/// Écran "Correction IA" — V2 selon maquette P4.
///
/// Affiché quand l'utilisateur lance une correction (manuelle ou retry) sur
/// une ou plusieurs copies. Affiche l'orbe sweep gradient rotative pendant
/// le traitement Claude, avec les 5 steps du protocole.
///
/// Auto-pop quand toutes les copies sont gradées (ou en erreur).
class CorrectionIAScreen extends StatefulWidget {
  final String examId;
  final String? copyId; // Si null → correction de TOUTES les copies pending

  const CorrectionIAScreen({
    super.key,
    required this.examId,
    this.copyId,
  });

  @override
  State<CorrectionIAScreen> createState() => _CorrectionIAScreenState();
}

class _CorrectionIAScreenState extends State<CorrectionIAScreen>
    with TickerProviderStateMixin {
  late final AnimationController _orbCtrl;
  late final AnimationController _progressCtrl;

  // Steps du protocole de correction (alignés avec grade-copy v6)
  static const _steps = [
    _Step('OCR manuscrit', Icons.text_fields_rounded),
    _Step('Compréhension du sens', Icons.psychology_outlined),
    _Step('Alignement corrigé (RAG)', Icons.search_rounded),
    _Step('Note par question', Icons.fact_check_outlined),
    _Step('Score de confiance', Icons.verified_outlined),
  ];

  int _currentStep = 0;
  bool _hasStarted = false;
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _startTime = DateTime.now();
    _animateSteps();
    _watchCompletion();
  }

  Future<void> _animateSteps() async {
    // Avance d'un step toutes les 2.5 secondes (simule la progression)
    for (int i = 1; i < _steps.length; i++) {
      await Future.delayed(const Duration(milliseconds: 2500));
      if (mounted) setState(() => _currentStep = i);
    }
  }

  /// Surveille la fin de la correction (polling du status des copies).
  Future<void> _watchCompletion() async {
    if (_hasStarted) return;
    _hasStarted = true;

    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      final examSvc = context.read<ExamService>();
      final copies = examSvc.copiesFor(widget.examId);
      final target = widget.copyId == null
          ? copies
          : copies.where((c) => c.id == widget.copyId).toList();

      if (target.isEmpty) return;

      final allDone = target.every((c) =>
          c.status == CopyStatus.graded || c.status == CopyStatus.error);

      // Sécurité : si plus de 90 sec, on pop quand même
      final elapsed = DateTime.now().difference(_startTime);
      if (allDone || elapsed.inSeconds > 90) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
    }
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final examSvc = context.watch<ExamService>();
    final exam = examSvc.getExam(widget.examId);
    final copies = examSvc.copiesFor(widget.examId);
    final totalCopies = widget.copyId == null
        ? copies.length
        : copies.where((c) => c.id == widget.copyId).length;
    final gradedCount = widget.copyId == null
        ? copies.where((c) => c.status == CopyStatus.graded).length
        : copies
            .where(
                (c) => c.id == widget.copyId && c.status == CopyStatus.graded)
            .length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.4,
            colors: [Color(0xFF061832), AppColors.voidBg],
            stops: [0.0, 0.85],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header (titre + sous-titre)
              const SizedBox(height: 40),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Text(
                      'Correction en cours…',
                      textAlign: TextAlign.center,
                      style: AppFonts.fraunces(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _buildSubtitle(exam, totalCopies, gradedCount),
                      textAlign: TextAlign.center,
                      style: AppFonts.sans(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── ORBE SWEEP GRADIENT (centre)
              _AnimatedOrb(controller: _orbCtrl),

              const SizedBox(height: 32),

              // ── Steps
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: List.generate(_steps.length, (i) {
                    final isDone = i < _currentStep;
                    final isCurrent = i == _currentStep;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _StepRow(
                        step: _steps[i],
                        isDone: isDone,
                        isCurrent: isCurrent,
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 22),

              // ── Progress bar pulsante
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: AnimatedBuilder(
                  animation: _progressCtrl,
                  builder: (context, _) {
                    // Progression entre 55% et 72% (style maquette)
                    final value = 0.55 + 0.17 * _progressCtrl.value;
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: LinearProgressIndicator(
                        value: value,
                        minHeight: 3,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.07),
                        valueColor: const AlwaysStoppedAnimation(
                            AppColors.profPrimary),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 18),

              // ── Confiance / info technique
              Text(
                'Protocole correcteur expert · v6',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 1.5,
                ),
              ),

              const Spacer(),

              // ── Bouton "Continuer en arrière-plan"
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Continuer en arrière-plan',
                    style: AppFonts.sans(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildSubtitle(Exam? exam, int total, int done) {
    if (exam == null) return 'Veuillez patienter…';
    final title = exam.title.length > 28
        ? '${exam.title.substring(0, 25)}…'
        : exam.title;
    if (widget.copyId == null) {
      return '$title · $done/$total copies traitées';
    }
    return '$title · Copie en cours';
  }
}

class _Step {
  final String label;
  final IconData icon;
  const _Step(this.label, this.icon);
}

/// Orbe animée avec sweep gradient rotatif (style maquette P4).
class _AnimatedOrb extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedOrb({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Halo lumineux extérieur
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.profPrimary.withValues(alpha: 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Orbe rotative — sweep gradient
            Transform.rotate(
              angle: controller.value * 6.28319, // 2π
              child: Container(
                width: 140,
                height: 140,
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
              ),
            ),
            // Centre sombre (creux de l'orbe)
            Container(
              width: 128,
              height: 128,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFF061228), AppColors.voidBg],
                ),
              ),
            ),
            // Icône bot centrale (contre-rotation pour rester droite)
            Transform.rotate(
              angle: -controller.value * 6.28319,
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
                size: 36,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Une ligne de step (avec checkmark, dot pulsant ou cercle vide).
class _StepRow extends StatelessWidget {
  final _Step step;
  final bool isDone;
  final bool isCurrent;
  const _StepRow({
    required this.step,
    required this.isDone,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDone
        ? AppColors.profPrimary
        : isCurrent
            ? AppColors.primaryLight
            : AppColors.textMuted.withValues(alpha: 0.4);
    final bgColor = isDone || isCurrent
        ? color.withValues(alpha: 0.08)
        : Colors.transparent;
    final borderColor = isDone || isCurrent
        ? color.withValues(alpha: 0.3)
        : AppColors.borderSubtle;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone || isCurrent
                  ? color.withValues(alpha: 0.2)
                  : Colors.transparent,
              border: Border.all(color: color, width: 1.5),
            ),
            child: isDone
                ? const Icon(Icons.check, size: 9, color: AppColors.profPrimary)
                : isCurrent
                    ? Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color,
                          ),
                        ),
                      )
                    : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.label,
              style: AppFonts.sans(
                fontSize: 11,
                color: color,
                fontWeight: isCurrent || isDone
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ),
          if (isDone)
            Text(
              '✓',
              style: AppFonts.sans(
                fontSize: 11,
                color: AppColors.profPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (isCurrent)
            Icon(
              Icons.sync_rounded,
              size: 12,
              color: color,
            ),
        ],
      ),
    );
  }
}
