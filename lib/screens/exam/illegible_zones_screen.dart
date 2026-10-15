import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../models/exam.dart';
import '../../models/question.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/smart_image.dart';
import 'correction_ia_screen.dart';

/// Écran Zone illisible (Human-in-the-Loop) — V2 selon maquette P5.
///
/// Liste toutes les questions d'une copie où l'IA a détecté une zone
/// incompréhensible (`methode_utilisee = ZONE_INCOMPREHENSIBLE`). Le prof
/// peut soit :
///   - saisir le texte manquant pour chaque zone → relance la correction
///   - OU bypasser une zone (la note reste à 0)
///
/// Le marqueur magique côté backend est `[ZONE_ILLISIBLE]` en début de comment.
class IllegibleZonesScreen extends StatefulWidget {
  final String copyId;

  const IllegibleZonesScreen({super.key, required this.copyId});

  @override
  State<IllegibleZonesScreen> createState() => _IllegibleZonesScreenState();
}

class _IllegibleZonesScreenState extends State<IllegibleZonesScreen> {
  // leafId → controller (transcription saisie par le prof)
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getController(String leafId) =>
      _controllers.putIfAbsent(leafId, () => TextEditingController());

  /// Liste plate de toutes les questions feuilles de l'examen.
  List<({Question parent, Question leaf})> _flattenLeaves(Exam exam) {
    final out = <({Question parent, Question leaf})>[];
    for (final q in exam.questions) {
      if (q.isLeaf) {
        out.add((parent: q, leaf: q));
      } else {
        for (final sub in q.subQuestions) {
          out.add((parent: q, leaf: Question(
            id: sub.id,
            label: sub.label,
            statement: sub.statement,
            points: sub.points,
          )));
        }
      }
    }
    return out;
  }

  Future<void> _relaunchCorrection(StudentCopy copy) async {
    if (copy.isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Notes figées : copie publiée au casier depuis plus de 3 jours.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);

    // Construit la liste des corrections manuelles à partir des champs remplis
    final manualCorrections = <Map<String, dynamic>>[];
    _controllers.forEach((leafId, ctrl) {
      final text = ctrl.text.trim();
      if (text.isNotEmpty) {
        manualCorrections.add({
          'leafId': leafId,
          'texte_corrige': text,
        });
      }
    });

    if (manualCorrections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Saisissez au moins une transcription avant de relancer.'),
        ),
      );
      setState(() => _saving = false);
      return;
    }

    try {
      // Lance la correction avec les manualCorrections puis affiche l'orbe
      await context
          .read<ExamService>()
          .startCorrection(copy.id, manualCorrections: manualCorrections);
      if (!mounted) return;
      // Remplace l'écran par l'écran orbe (auto-pop à la fin)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CorrectionIAScreen(
            examId: copy.examId,
            copyId: copy.id,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec : $e'),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final examSvc = context.watch<ExamService>();
    final copy = examSvc.getCopy(widget.copyId);
    if (copy == null) {
      return const Scaffold(
        body: Center(child: Text('Copie introuvable')),
      );
    }
    final exam = examSvc.getExam(copy.examId);
    if (exam == null) {
      return const Scaffold(
        body: Center(child: Text('Examen introuvable')),
      );
    }

    // Récupère uniquement les questions avec une zone illisible
    final leaves = _flattenLeaves(exam);
    final illegibleQuestions = leaves.where((entry) {
      final grade = copy.grades.firstWhere(
        (g) => g.questionId == entry.leaf.id,
        orElse: () => QuestionGrade(questionId: entry.leaf.id, score: 0),
      );
      return grade.comment.startsWith('[ZONE_ILLISIBLE]');
    }).toList();

    final zoneCount = illegibleQuestions.length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.6),
            radius: 1.4,
            colors: [
              AppColors.warning.withValues(alpha: 0.06),
              AppColors.voidBg,
            ],
            stops: const [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Header back + titre + sous-titre + badge orange
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _BackButton(
                            onTap: () => Navigator.maybePop(context)),
                        const Spacer(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '← ${copy.studentName.toUpperCase()}',
                      style: AppFonts.mono(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Zones illisibles',
                      style: AppFonts.fraunces(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Votre validation est requise',
                      style: AppFonts.sans(
                        fontSize: 12,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.12),
                        border: Border.all(
                            color:
                                AppColors.warning.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 14, color: AppColors.warning),
                          const SizedBox(width: 6),
                          Text(
                            '$zoneCount zone${zoneCount > 1 ? 's' : ''} en attente',
                            style: AppFonts.mono(
                              fontSize: 11,
                              color: AppColors.warning,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // A5 — Aperçu des pages de la copie (zoom & swipe)
              if (copy.pageImages.isNotEmpty && zoneCount > 0)
                _CopyImageViewer(pages: copy.pageImages),

              // ── Liste des zones
              Expanded(
                child: zoneCount == 0
                    ? _emptyState(context)
                    : ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: illegibleQuestions.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final entry = illegibleQuestions[i];
                          final ctrl = _getController(entry.leaf.id);
                          final grade = copy.grades.firstWhere(
                            (g) => g.questionId == entry.leaf.id,
                            orElse: () => QuestionGrade(
                                questionId: entry.leaf.id, score: 0),
                          );
                          // Strip du marqueur pour afficher juste l'explication
                          final cleanComment = grade.comment
                              .replaceFirst(
                                  RegExp(r'^\[ZONE_ILLISIBLE\][\s:]*'), '')
                              .trim();
                          return _IllegibleZoneCard(
                            parentLabel: entry.parent.label,
                            leafLabel: entry.leaf.label,
                            statement: entry.leaf.statement,
                            comment: cleanComment,
                            maxPoints: entry.leaf.points,
                            controller: ctrl,
                          );
                        },
                      ),
              ),

              // Grille v5 : la validation manuelle (Human-in-the-Loop) est
              // incluse dans les crédits déjà débités.
              if (zoneCount > 0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '✓ Relance incluse : aucun crédit supplémentaire.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),

              // ── Bottom actions
              if (zoneCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Plus tard'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: _GradientButton(
                          label: 'RELANCER L\'IA',
                          loading: _saving,
                          onTap: () => _relaunchCorrection(copy),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.profPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: const Icon(Icons.check_circle_outline,
                  color: AppColors.profPrimary, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              'Aucune zone illisible',
              style: AppFonts.fraunces(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'L\'IA a pu lire l\'intégralité de la copie.',
              textAlign: TextAlign.center,
              style: AppFonts.sans(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// COMPOSANTS
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// A5 (Sprint 5) — Aperçu des pages de la copie avec zoom, pour aider le
/// prof à transcrire les zones illisibles. Swipe horizontal entre pages,
/// pinch-to-zoom pour lire les caractères.
class _CopyImageViewer extends StatefulWidget {
  final List<String> pages;
  const _CopyImageViewer({required this.pages});

  @override
  State<_CopyImageViewer> createState() => _CopyImageViewerState();
}

class _CopyImageViewerState extends State<_CopyImageViewer> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _openFullscreen(int initialPage) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _CopyImageFullscreen(
          pages: widget.pages,
          initialPage: initialPage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'COPIE DE L\'ÉLÈVE',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 1.8,
                ),
              ),
              const Spacer(),
              Text(
                'Page ${_currentPage + 1} / ${widget.pages.length}',
                style: AppFonts.mono(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.card,
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: widget.pages.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (context, i) {
                  return GestureDetector(
                    onTap: () => _openFullscreen(i),
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: SmartImage(
                        path: widget.pages[i],
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.zoom_in_rounded,
                  size: 12, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text(
                'Pincez pour zoomer · Touchez pour plein écran',
                style: AppFonts.sans(
                  fontSize: 10,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A5 — Vue plein écran d'une page de copie (zoom maximum).
class _CopyImageFullscreen extends StatefulWidget {
  final List<String> pages;
  final int initialPage;
  const _CopyImageFullscreen({
    required this.pages,
    required this.initialPage,
  });

  @override
  State<_CopyImageFullscreen> createState() => _CopyImageFullscreenState();
}

class _CopyImageFullscreenState extends State<_CopyImageFullscreen> {
  late final PageController _ctrl =
      PageController(initialPage: widget.initialPage);
  late int _current = widget.initialPage;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Page ${_current + 1} / ${widget.pages.length}',
          style: AppFonts.mono(
            fontSize: 12,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.pages.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (context, i) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 6,
            child: Center(
              child: SmartImage(
                path: widget.pages[i],
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Carte d'une zone illisible — avec faux texte mock + zone surlignée + input.
class _IllegibleZoneCard extends StatelessWidget {
  final String parentLabel;
  final String leafLabel;
  final String statement;
  final String comment;
  final double maxPoints;
  final TextEditingController controller;

  const _IllegibleZoneCard({
    required this.parentLabel,
    required this.leafLabel,
    required this.statement,
    required this.comment,
    required this.maxPoints,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.25),
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — question
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '${parentLabel.toUpperCase()} · $leafLabel',
                    style: AppFonts.mono(
                      fontSize: 10,
                      color: AppColors.warning,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '/ ${_fmt(maxPoints)} pts',
                  style: AppFonts.mono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Mock visuel copie (lignes + zone surlignée)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                border: Border.all(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _fakeLine(0.9, alpha: 0.4),
                      const SizedBox(height: 6),
                      _fakeLine(0.7, alpha: 0.3),
                      const SizedBox(height: 6),
                      // Zone surlignée
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          border: Border.all(
                            color: AppColors.warning
                                .withValues(alpha: 0.5),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 12, color: AppColors.warning),
                            const SizedBox(width: 6),
                            Text(
                              'Texte non reconnu',
                              style: AppFonts.mono(
                                fontSize: 10,
                                color: AppColors.warning,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      _fakeLine(0.85, alpha: 0.3),
                      const SizedBox(height: 6),
                      _fakeLine(0.55, alpha: 0.2),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Statement de la question
          if (statement.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                statement,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          // Label input
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Text(
              'RETRANSCRIVEZ CE QUE VOUS LISEZ',
              style: AppFonts.mono(
                fontSize: 9,
                color: AppColors.textMuted,
                letterSpacing: 2,
              ),
            ),
          ),
          // Input
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              style: AppFonts.sans(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: comment.isNotEmpty
                    ? comment
                    : 'Ex : La dérivée de f(x) = x² est f\'(x) = 2x',
                hintStyle: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
                filled: true,
                fillColor: const Color(0x0AFFFFFF),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(
                    color: AppColors.borderSubtle,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: const BorderSide(
                    color: AppColors.warning,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fakeLine(double widthFactor, {double alpha = 0.3}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 7,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

/// Bouton retour circulaire.
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

/// Bouton gradient vert pleine largeur (style maquette).
class _GradientButton extends StatelessWidget {
  final String label;
  final bool loading;
  final VoidCallback onTap;

  const _GradientButton({
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
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: loading ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      label,
                      style: AppFonts.mono(
                        fontSize: 11,
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
