import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../models/correction_source.dart';
import '../../models/exam.dart';
import '../../services/establishment_service.dart';
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
class ExamDetailScreen extends StatefulWidget {
  final String examId;
  const ExamDetailScreen({super.key, required this.examId});

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  final TextEditingController _searchCtl = TextEditingController();
  String _searchQuery = '';

  String get examId => widget.examId;

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final examSvc = context.watch<ExamService>();
    final exam = examSvc.getExam(examId);
    if (exam == null) {
      return const Scaffold(body: Center(child: Text('Examen introuvable')));
    }
    final allCopies = examSvc.copiesFor(examId);
    final copiesToReview =
        allCopies.where((c) => c.needsReview).toList();
    final q = _searchQuery.trim().toLowerCase();
    final copies = q.isEmpty
        ? allCopies
        : allCopies.where((c) {
            final n = c.studentName.toLowerCase();
            final r = (c.studentRef ?? '').toLowerCase();
            return n.contains(q) || r.contains(q);
          }).toList();
    final graded =
        allCopies.where((c) => c.status == CopyStatus.graded).length;
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
                        value: '${allCopies.length}',
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
                // ━━━ Section "Copies à reprendre" (si nécessaire) ━━━
                if (copiesToReview.isNotEmpty) ...[
                  _ToReviewSection(
                    copies: copiesToReview,
                    totalPoints: exam.computedTotal == 0
                        ? exam.totalPoints
                        : exam.computedTotal,
                  ),
                  const SizedBox(height: 18),
                ],

                // ━━━ Copies des élèves ━━━
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
                    if (allCopies.isNotEmpty && canScan)
                      TextButton.icon(
                        onPressed: () => _exportExcel(context, examId),
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('Excel'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                // Barre de recherche (visible dès 3 copies)
                if (allCopies.length >= 3) ...[
                  _CopySearchBar(
                    controller: _searchCtl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    onClear: () {
                      _searchCtl.clear();
                      setState(() => _searchQuery = '');
                    },
                  ),
                  const SizedBox(height: 10),
                ],

                if (allCopies.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RankingButton(examId: examId),
                  ),
                if (allCopies.isEmpty)
                  _EmptyCopies(canScan: canScan)
                else if (copies.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      border: Border.all(
                          color: AppColors.borderSubtle),
                      borderRadius:
                          BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.search_off_rounded,
                          color: AppColors.textMuted,
                          size: 28,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Aucune copie pour « $_searchQuery »',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PublishToCasierButton(examId: examId),
                    PrimaryButton(
                      label: 'Scanner une copie',
                      icon: Icons.qr_code_scanner,
                      onPressed: () => _scanCopyOrShowLimit(context, examSvc),
                    ),
                  ],
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

  /// Ouvre l'écran "Nouvel élève". Le contrôle des crédits se fait au
  /// lancement de la correction (réservation selon le nombre de pages —
  /// grille v5), pas à l'ouverture du scan : scanner ne coûte rien.
  void _scanCopyOrShowLimit(BuildContext context, ExamService examSvc) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NewStudentScreen(examId: examId)),
    );
  }

  static String _sourceLabel(CorrectionSource s) {
    // v3 : on peut avoir corrigé + cours combinés
    final parts = <String>[];
    final ak = s.effectiveAnswerKeyPaths.length;
    final co = s.effectiveCoursePaths.length;
    if (ak > 0) parts.add('Corrigé ($ak)');
    if (co > 0) parts.add('Cours ($co)');
    final hasAi = (s.generatedContent ?? '').trim().isNotEmpty;
    if (hasAi) {
      parts.add('IA ${s.validated ? "validée" : "à valider"}');
    }
    if (parts.isEmpty) return s.type.title;
    return parts.join(' + ');
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

/// Bouton "Envoyer au casier" : visible uniquement quand le prof appartient
/// à un établissement et qu'au moins une copie est graded mais pas encore
/// publiée. Confirme avant d'envoyer.
class _PublishToCasierButton extends StatefulWidget {
  final String examId;
  const _PublishToCasierButton({required this.examId});

  @override
  State<_PublishToCasierButton> createState() =>
      _PublishToCasierButtonState();
}

class _PublishToCasierButtonState extends State<_PublishToCasierButton> {
  bool _sending = false;

  Future<void> _confirmAndPublish(BuildContext context, int n) async {
    // Michel : la publication va UNIQUEMENT au casier de l'école
    // rattachée à cet examen (exam.establishmentId).
    // Si l'examen est solo (null) → publication interdite.
    final examSvc = context.read<ExamService>();
    final estabSvc = context.read<EstablishmentService>();
    final exam = examSvc.getExam(widget.examId);
    if (exam == null) return;

    if (exam.establishmentId == null) {
      // Solo → pas de casier
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(
            'Examen personnel',
            style: AppFonts.fraunces(
                fontSize: 18, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Cet examen a été créé en mode Personnel (solo). '
            'Les notes ne peuvent pas être envoyées à un casier école. '
            'Créez un nouvel examen en le rattachant à une école pour '
            'partager les notes avec l\'admin.',
            style: AppFonts.sans(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Récupère le nom de l'école cible
    final target = estabSvc.myMemberships.firstWhere(
      (m) => m.establishmentId == exam.establishmentId,
      orElse: () => MembershipSummary(
        membershipId: '',
        establishmentId: exam.establishmentId!,
        establishmentName: 'l\'école',
        role: 'teacher',
        joinedAt: DateTime.now(),
      ),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Envoyer au casier ?',
          style: AppFonts.fraunces(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$n note${n > 1 ? "s" : ""} seront envoyées au casier de :',
              style: AppFonts.sans(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.adminPrimary.withValues(alpha: 0.08),
                border: Border.all(
                    color:
                        AppColors.adminPrimary.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_rounded,
                      color: AppColors.adminPrimary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      target.establishmentName,
                      style: AppFonts.sans(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.adminPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Aucune autre école ne verra ces notes.',
              style: AppFonts.sans(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Envoyer',
              style: TextStyle(
                color: AppColors.profPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    setState(() => _sending = true);
    try {
      final count = await context
          .read<ExamService>()
          .publishExamCopies(widget.examId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$count note${count > 1 ? "s" : ""} '
              'envoyée${count > 1 ? "s" : ""} au casier de l\'école.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.profPrimary,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur d\'envoi : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estab = context.watch<EstablishmentService>();
    final examSvc = context.watch<ExamService>();

    // Visible uniquement pour un membre d'établissement (admin ou teacher)
    if (!estab.hasEstablishment) return const SizedBox.shrink();

    final copies = examSvc.copiesFor(widget.examId);
    final toPublish = copies
        .where((c) => c.status == CopyStatus.graded && !c.isPublished)
        .length;
    final published =
        copies.where((c) => c.isPublished).length;

    if (toPublish == 0 && published == 0) return const SizedBox.shrink();

    if (toPublish == 0) {
      // Tout est publié → affiche un statut "Envoyé au casier"
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.profPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: AppColors.profPrimary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline,
                  color: AppColors.profPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                '$published note${published > 1 ? "s" : ""} envoyée${published > 1 ? "s" : ""} au casier',
                style: AppFonts.sans(
                  fontSize: 12,
                  color: AppColors.profPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
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
            onTap: _sending
                ? null
                : () => _confirmAndPublish(context, toPublish),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_sending)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  else
                    const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  const SizedBox(width: 10),
                  Text(
                    _sending
                        ? 'ENVOI…'
                        : 'ENVOYER $toPublish NOTE${toPublish > 1 ? "S" : ""} AU CASIER',
                    style: AppFonts.mono(
                      fontSize: 12,
                      color: Colors.white,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

/// Tile copie élève — style maquette P6 :
/// avatar coloré (gradient déterministe par nom) + nom + détail Q + note Fraunces.
class _CopyTile extends StatelessWidget {
  final StudentCopy copy;
  final double totalPoints;
  final VoidCallback onTap;
  const _CopyTile({
    required this.copy,
    required this.totalPoints,
    required this.onTap,
  });

  static const _avatarGradients = <Gradient>[
    LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF06B6D4)]),
    LinearGradient(colors: [Color(0xFF059669), Color(0xFF2DD4BF)]),
    LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF3B82F6)]),
    LinearGradient(colors: [Color(0xFFD97706), Color(0xFFEF4444)]),
    LinearGradient(colors: [Color(0xFF9D174D), Color(0xFF7C3AED)]),
  ];

  // Hash stable du nom pour avoir TOUJOURS le même avatar pour le même élève
  Gradient get _gradient =>
      _avatarGradients[copy.studentName.hashCode.abs() %
          _avatarGradients.length];

  bool get _isOffTopic =>
      copy.generalComment.startsWith('⛔ HORS-SUJET — ');

  bool get _hasIllegibleZone =>
      copy.grades.any((g) => g.comment.startsWith('[ZONE_ILLISIBLE]'));

  Color _noteColor(double percent) {
    if (percent >= 75) return AppColors.profPrimary;
    if (percent >= 50) return AppColors.primaryLight;
    if (percent >= 30) return AppColors.warning;
    return AppColors.danger;
  }

  String _shortGradesDetail() {
    final visible = copy.grades.take(3).toList();
    if (visible.isEmpty) return '';
    return visible
        .asMap()
        .entries
        .map((e) => 'Q${e.key + 1}:${_fmt(e.value.score)}')
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final isGraded = copy.status == CopyStatus.graded;
    final isProcessing = copy.status == CopyStatus.processing;
    final isError = copy.status == CopyStatus.error;
    final percent = totalPoints == 0
        ? 0.0
        : (copy.totalScore / totalPoints).clamp(0, 1).toDouble() * 100;
    final isFlagged = _hasIllegibleZone || isError;

    return Material(
      color: isFlagged
          ? AppColors.warning.withValues(alpha: 0.04)
          : AppColors.card,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isFlagged
                  ? AppColors.warning.withValues(alpha: 0.3)
                  : AppColors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar gradient
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: _gradient,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(copy.studentName),
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Nom + détail
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.studentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.sans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLine(isGraded, isProcessing, isError),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.sans(
                        fontSize: 10,
                        // Tous les statuts "non terminés" (en cours, en
                        // attente, erreur, hors-sujet) sont en rouge ; les
                        // copies illisibles restent en orange.
                        color: _isOffTopic ||
                                isProcessing ||
                                isError ||
                                (!isGraded && !isProcessing)
                            ? AppColors.danger
                            : _hasIllegibleZone
                                ? AppColors.warning
                                : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              // Note + confiance
              if (isGraded) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: AppFonts.fraunces(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _noteColor(percent),
                        ),
                        children: [
                          TextSpan(text: _fmt(copy.totalScore)),
                          TextSpan(
                            text: '/${_fmt(totalPoints)}',
                            style: AppFonts.sans(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${(copy.confidence * 100).toStringAsFixed(0)}%',
                      style: AppFonts.mono(
                        fontSize: 9,
                        color: copy.confidence >= 0.85
                            ? AppColors.profPrimary
                            : copy.confidence >= 0.6
                                ? AppColors.warning
                                : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ] else if (isProcessing) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.profPrimary,
                  ),
                ),
              ] else if (isError) ...[
                const SizedBox(width: 8),
                const Icon(Icons.error_outline,
                    color: AppColors.danger, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _statusLine(bool isGraded, bool isProcessing, bool isError) {
    if (_isOffTopic) return '⛔ Hors-sujet';
    if (_hasIllegibleZone) return '⚠️ Zone illisible';
    if (isProcessing) return 'Correction en cours…';
    if (isError) return 'Échec — Appuyez pour réessayer';
    if (isGraded) {
      final detail = _shortGradesDetail();
      return detail.isNotEmpty
          ? detail
          : '${copy.pageImages.length} page${copy.pageImages.length > 1 ? 's' : ''}';
    }
    return '${copy.pageImages.length} page${copy.pageImages.length > 1 ? 's' : ''} · En attente';
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Sprint 3 — Recherche copies + section "Copies à reprendre"
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Barre de recherche dans une liste de copies (prénom, nom, matricule).
class _CopySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _CopySearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: AppFonts.sans(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Rechercher (prénom, nom, matricule)…',
        hintStyle: AppFonts.sans(
          fontSize: 12.5,
          color: AppColors.textMuted.withValues(alpha: 0.7),
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: AppColors.textMuted,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppColors.textMuted,
                onPressed: onClear,
                splashRadius: 18,
              ),
        filled: true,
        fillColor: AppColors.card,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          borderSide: const BorderSide(
              color: AppColors.profPrimary, width: 1.4),
        ),
      ),
    );
  }
}

/// Section "Copies à reprendre" — collapsible (extension) avec les copies
/// nécessitant l'attention du prof (hors-sujet, illisibles, erreurs).
class _ToReviewSection extends StatelessWidget {
  final List<StudentCopy> copies;
  final double totalPoints;
  const _ToReviewSection({
    required this.copies,
    required this.totalPoints,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.06),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Theme(
        // Supprime le séparateur natif du ExpansionTile
        data: Theme.of(context)
            .copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: copies.length <= 3,
          tilePadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          iconColor: AppColors.warning,
          collapsedIconColor: AppColors.warning,
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.priority_high_rounded,
              color: AppColors.warning,
              size: 18,
            ),
          ),
          title: Text(
            'COPIES À REPRENDRE',
            style: AppFonts.mono(
              fontSize: 10.5,
              color: AppColors.warning,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '${copies.length} copie${copies.length != 1 ? "s" : ""} nécessite${copies.length != 1 ? "nt" : ""} votre attention',
              style: AppFonts.sans(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          children: copies.map((c) {
            return Padding(
              padding:
                  const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: _CopyTile(
                copy: c,
                totalPoints: totalPoints,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        StudentCopyDetailScreen(copyId: c.id),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
