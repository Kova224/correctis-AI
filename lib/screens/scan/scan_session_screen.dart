import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/copy.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import 'new_student_screen.dart';

/// Étapes 2 → 5 : scan multi-pages, gestion, validation, passage au suivant (§3.4).
class ScanSessionScreen extends StatefulWidget {
  final String copyId;
  const ScanSessionScreen({super.key, required this.copyId});

  @override
  State<ScanSessionScreen> createState() => _ScanSessionScreenState();
}

class _ScanSessionScreenState extends State<ScanSessionScreen> {
  final _picker = ImagePicker();
  bool _saving = false;

  StudentCopy get _copy =>
      context.read<ExamService>().getCopy(widget.copyId)!;

  Future<void> _scanPage() async {
    final f = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (f == null) return;
    final copy = _copy;
    copy.pageImages.add(f.path);
    await context.read<ExamService>().updateCopy(copy);
    if (mounted) setState(() {});
  }

  Future<void> _addFromGallery() async {
    final files = await _picker.pickMultiImage(imageQuality: 70);
    if (files.isEmpty) return;
    final copy = _copy;
    copy.pageImages.addAll(files.map((f) => f.path));
    await context.read<ExamService>().updateCopy(copy);
    if (mounted) setState(() {});
  }

  Future<void> _removePage(int index) async {
    final copy = _copy;
    copy.pageImages.removeAt(index);
    await context.read<ExamService>().updateCopy(copy);
    if (mounted) setState(() {});
  }

  Future<void> _movePage(int oldIndex, int newIndex) async {
    final copy = _copy;
    if (newIndex > oldIndex) newIndex--;
    final item = copy.pageImages.removeAt(oldIndex);
    copy.pageImages.insert(newIndex, item);
    await context.read<ExamService>().updateCopy(copy);
    if (mounted) setState(() {});
  }

  Future<bool> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        title: const Text('Quitter sans valider ?'),
        content: const Text(
          'La copie de cet élève ne sera pas envoyée à la correction.\n\n'
          'Vous pourrez la reprendre depuis la liste des copies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer le scan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Quitter',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _validateCopy({required bool startNew}) async {
    final copy = _copy;
    if (copy.pageImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Scannez au moins une page avant de valider.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      // Marquer pending puis lancer la correction asynchrone
      copy.status = CopyStatus.pending;
      await context.read<ExamService>().updateCopy(copy);
      // Déclenche la correction en arrière-plan (non bloquant)
      // ignore: unawaited_futures
      context.read<ExamService>().startCorrection(copy.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Copie de ${copy.studentName} envoyée à la correction'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (startNew) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => NewStudentScreen(examId: copy.examId),
        ));
      } else {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final examSvc = context.watch<ExamService>();
    final copy = examSvc.getCopy(widget.copyId);
    if (copy == null) {
      return const Scaffold(body: Center(child: Text('Copie introuvable')));
    }
    final pages = copy.pageImages;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final allow = await _confirmExit();
        if (allow && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Column(
          children: [
            RoundedHeader(
              height: 220,
              showBackButton: true,
              onBack: () async {
                final allow = await _confirmExit();
                if (allow && mounted) Navigator.of(context).pop();
              },
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.qr_code_scanner,
                        color: Colors.white, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      copy.studentName.toUpperCase(),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                    ),
                    if (copy.studentRef != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        copy.studentRef!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '${pages.length} page${pages.length > 1 ? 's' : ''} scannée${pages.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: 'Scanner',
                          icon: Icons.camera_alt,
                          onPressed: _scanPage,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 54,
                        width: 54,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.zero,
                            backgroundColor: AppColors.primary,
                          ),
                          onPressed: _addFromGallery,
                          child: const Icon(Icons.image_outlined,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (pages.isEmpty)
                    SectionCard(
                      child: Column(
                        children: [
                          const Icon(Icons.description_outlined,
                              size: 48, color: AppColors.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            'Aucune page scannée',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Scannez les pages de cette copie une à une. Vous pourrez réorganiser ou supprimer.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    )
                  else
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Pages',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              Text(
                                '${pages.length} au total',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Glissez-déposez pour réorganiser.',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: pages.length,
                            onReorder: _movePage,
                            itemBuilder: (context, i) {
                              final path = pages[i];
                              return Padding(
                                key: ValueKey('${path}_$i'),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _PageRow(
                                  path: path,
                                  index: i,
                                  total: pages.length,
                                  onRemove: () => _removePage(i),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _validateCopy(startNew: false),
                    icon: const Icon(Icons.check),
                    label: const Text('Terminer cette copie'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: 'Nouvel élève',
                    icon: Icons.person_add_alt_1,
                    loading: _saving,
                    onPressed: () => _validateCopy(startNew: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PageRow extends StatelessWidget {
  final String path;
  final int index;
  final int total;
  final VoidCallback onRemove;

  const _PageRow({
    required this.path,
    required this.index,
    required this.total,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: const Icon(Icons.drag_indicator,
                  color: AppColors.textMuted),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 60,
              height: 80,
              child: _SafeImage(path: path),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Page ${index + 1} / $total',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scan capturé',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.danger),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _SafeImage extends StatelessWidget {
  final String path;
  const _SafeImage({required this.path});

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        color: AppColors.divider,
        child: const Icon(Icons.image, color: AppColors.textMuted),
      );
}
