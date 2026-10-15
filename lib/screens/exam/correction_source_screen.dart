import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../../config/supabase_config.dart';
import '../../models/correction_source.dart';
import '../../services/ai_correction_service.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_resizer.dart';
import '../../utils/retry.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/rounded_header.dart';
import '../../widgets/section_card.dart';
import 'exam_detail_screen.dart';

/// Écran "Source de correction" — v3 (juin 2026)
///
/// Le prof peut maintenant fournir SIMULTANÉMENT :
///   • Corrigé type (un ou plusieurs documents)
///   • Cours / support (un ou plusieurs documents)
///   • OU bien activer la Génération IA (mode exclusif des deux ci-dessus)
class CorrectionSourceScreen extends StatefulWidget {
  final String examId;
  const CorrectionSourceScreen({super.key, required this.examId});

  @override
  State<CorrectionSourceScreen> createState() => _CorrectionSourceScreenState();
}

class _CorrectionSourceScreenState extends State<CorrectionSourceScreen> {
  // Trois sources INDÉPENDANTES — l'utilisateur peut activer celles qu'il veut.
  bool _useAnswerKey = true;
  bool _useCourse = false;
  bool _useAi = false;

  // Documents par source
  final List<String> _answerKeyDocs = <String>[];
  final List<String> _courseDocs = <String>[];

  // IA générée
  final TextEditingController _generatedCtrl = TextEditingController();
  bool _generating = false;
  bool _aiValidated = false;

  bool _saving = false;
  final _uuid = const Uuid();

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  @override
  void dispose() {
    _generatedCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDocFor(List<String> bucket) async {
    // ⚠️ Formats limités à ceux acceptés par Claude vision/document :
    //   - Images : JPG, JPEG, PNG, WEBP
    //   - Document : PDF
    // DOCX/HEIC volontairement exclus car Claude ne les supporte pas.
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: true,
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.path != null) bucket.add(f.path!);
      }
    });
  }

  Future<void> _pickFromCameraFor(List<String> bucket) async {
    final XFile? f =
        await ImagePicker().pickImage(source: ImageSource.camera);
    if (f != null) setState(() => bucket.add(f.path));
  }

  /// Import direct depuis la galerie photo du téléphone.
  /// Alternative rapide à _pickDocFor quand le prof ne veut pas naviguer
  /// dans le browser de fichiers pour trouver ses images.
  Future<void> _pickFromGalleryFor(List<String> bucket) async {
    final List<XFile> files =
        await ImagePicker().pickMultiImage(imageQuality: 75);
    if (files.isNotEmpty) {
      setState(() => bucket.addAll(files.map((f) => f.path)));
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final exam = context.read<ExamService>().getExam(widget.examId)!;
      final text = await AiCorrectionService().generateAnswerKey(exam);
      _generatedCtrl.text = text;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// Upload des documents locaux vers Supabase Storage, renvoie les URLs publiques.
  /// ⚠️ PAS de fallback chemin local — si l'upload échoue, on throw.
  /// Sans URL publique, l'IA ne pourrait pas comparer la copie au corrigé.
  Future<List<String>> _uploadDocs(
      List<String> paths, String folder) async {
    if (paths.isEmpty) return const [];
    final userId = _client.auth.currentUser?.id ?? 'anon';
    final urls = <String>[];
    for (final path in paths) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        urls.add(path);
        continue;
      }
      // Resize si c'est une image (les PDFs sont laissés tels quels par le helper).
      // Limite Anthropic = 2000px en multi-images, on cible 1800px.
      final resizedPath = await ImageResizer.resizeIfNeeded(path);

      final file = File(resizedPath);
      if (!file.existsSync()) {
        debugPrint('[_uploadDocs] fichier introuvable : $resizedPath');
        continue;
      }
      final dotIdx = resizedPath.lastIndexOf('.');
      final ext = dotIdx >= 0
          ? resizedPath.substring(dotIdx).toLowerCase()
          : '.jpg';
      final remotePath =
          '$userId/${widget.examId}/$folder/${_uuid.v4()}$ext';

      // Force le contentType MIME — sinon Supabase Storage utilise
      // application/octet-stream qui casse la validation pdf/image et
      // fait échouer l'upload silencieusement pour les PDFs.
      final contentType = _mimeTypeFor(ext);

      try {
        await RetryHelper.run(
          () => _client.storage.from(SupabaseConfig.subjectsBucket).upload(
                remotePath,
                file,
                fileOptions: sb.FileOptions(
                  contentType: contentType,
                  upsert: false,
                ),
              ),
        );
        final url = _client.storage
            .from(SupabaseConfig.subjectsBucket)
            .getPublicUrl(remotePath);
        urls.add(url);
        debugPrint(
            '[_uploadDocs] ✓ doc uploadé ($contentType) : $url');
      } catch (e) {
        debugPrint('[_uploadDocs] ✗ upload échoué : $e');
        throw 'Upload du document $folder échoué : $e';
      }
    }
    return urls;
  }

  /// MIME type explicite selon l'extension du fichier.
  /// Requis pour l'upload Supabase Storage : sans ça, il fallback sur
  /// application/octet-stream qui casse la validation MIME côté bucket.
  String _mimeTypeFor(String ext) {
    switch (ext) {
      case '.pdf':
        return 'application/pdf';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _save() async {
    // Validation : au moins UNE source doit être activée et remplie
    if (!_useAnswerKey && !_useCourse && !_useAi) {
      _snack('Activez au moins une source de correction.');
      return;
    }
    if (_useAnswerKey && _answerKeyDocs.isEmpty) {
      _snack('Ajoutez au moins un document de corrigé type.');
      return;
    }
    if (_useCourse && _courseDocs.isEmpty) {
      _snack('Ajoutez au moins un document de cours / support.');
      return;
    }
    if (_useAi) {
      if (_generatedCtrl.text.trim().isEmpty) {
        _snack('Générez d\'abord un corrigé IA.');
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
      // Upload des documents vers Storage
      final answerKeyUrls =
          _useAnswerKey ? await _uploadDocs(_answerKeyDocs, 'answer-keys') : const <String>[];
      final courseUrls =
          _useCourse ? await _uploadDocs(_courseDocs, 'courses') : const <String>[];

      // Détermine le type "primaire" pour rétro-compat (priorité : answerKey > course > aiGenerated)
      final CorrectionSourceType primaryType = _useAnswerKey
          ? CorrectionSourceType.answerKey
          : (_useCourse
              ? CorrectionSourceType.course
              : CorrectionSourceType.aiGenerated);

      final exam = context.read<ExamService>().getExam(widget.examId)!;
      exam.correctionSource = CorrectionSource(
        type: primaryType,
        answerKeyPaths: answerKeyUrls,
        coursePaths: courseUrls,
        generatedContent: _useAi ? _generatedCtrl.text : null,
        validated: _useAi ? _aiValidated : true,
      );
      await context.read<ExamService>().updateExam(exam);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => ExamDetailScreen(examId: widget.examId),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      // Affiche l'erreur d'upload au prof
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Enregistrement impossible'),
          content: SingleChildScrollView(
            child: Text(
              '$e\n\nVérifiez votre connexion internet et réessayez.',
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
                    'SOURCES DE CORRECTION',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vous pouvez combiner corrigé + cours',
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
                _MultiSourceCard(
                  title: 'Corrigé type',
                  subtitle:
                      'Photos / PDF du corrigé officiel — l\'IA s\'y réfère strictement.',
                  icon: Icons.fact_check_outlined,
                  enabled: _useAnswerKey,
                  onToggle: (v) {
                    setState(() {
                      _useAnswerKey = v;
                      if (v) _useAi = false; // exclu avec IA générée
                    });
                  },
                  child: _DocsPicker(
                    docs: _answerKeyDocs,
                    onPickFile: () => _pickDocFor(_answerKeyDocs),
                    onPickCamera: () => _pickFromCameraFor(_answerKeyDocs),
                    onPickGallery: () => _pickFromGalleryFor(_answerKeyDocs),
                    onRemove: (i) =>
                        setState(() => _answerKeyDocs.removeAt(i)),
                  ),
                ),
                const SizedBox(height: 14),
                _MultiSourceCard(
                  title: 'Cours / Support',
                  subtitle:
                      'PDF du cours ou support de référence — l\'IA évalue selon ces notions.',
                  icon: Icons.menu_book_outlined,
                  enabled: _useCourse,
                  onToggle: (v) {
                    setState(() {
                      _useCourse = v;
                      if (v) _useAi = false; // exclu avec IA générée
                    });
                  },
                  child: _DocsPicker(
                    docs: _courseDocs,
                    onPickFile: () => _pickDocFor(_courseDocs),
                    onPickCamera: () => _pickFromCameraFor(_courseDocs),
                    onPickGallery: () => _pickFromGalleryFor(_courseDocs),
                    onRemove: (i) => setState(() => _courseDocs.removeAt(i)),
                  ),
                ),
                const SizedBox(height: 14),
                _MultiSourceCard(
                  title: 'Génération IA',
                  subtitle:
                      'L\'IA propose un corrigé à partir du sujet — vous le validez.',
                  icon: Icons.auto_awesome,
                  enabled: _useAi,
                  // L'IA générée est exclusive : décocher corrigé & cours
                  onToggle: (v) {
                    setState(() {
                      _useAi = v;
                      if (v) {
                        _useAnswerKey = false;
                        _useCourse = false;
                      }
                    });
                  },
                  child: _AiGenerationBlock(
                    controller: _generatedCtrl,
                    generating: _generating,
                    onGenerate: _generate,
                    validated: _aiValidated,
                    onValidatedChanged: (v) =>
                        setState(() => _aiValidated = v),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Astuce : combinez corrigé type + cours pour une notation plus précise. L\'IA croise les deux sources.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Valider les sources',
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
}

// =============================================================================
// Carte de source (toggle + contenu replié si désactivé)
// =============================================================================
class _MultiSourceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final Widget child;
  const _MultiSourceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.enabled,
    required this.onToggle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onToggle,
                activeColor: AppColors.profPrimary,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 14),
            child,
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Picker de documents (réutilisé pour corrigé et cours)
// =============================================================================
class _DocsPicker extends StatelessWidget {
  final List<String> docs;
  final VoidCallback onPickFile;
  final VoidCallback onPickCamera;
  final VoidCallback onPickGallery;
  final ValueChanged<int> onRemove;
  const _DocsPicker({
    required this.docs,
    required this.onPickFile,
    required this.onPickCamera,
    required this.onPickGallery,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('Photo', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickGallery,
                icon: const Icon(Icons.photo_library_outlined, size: 16),
                label: const Text('Galerie', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickFile,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: const Text('PDF', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (docs.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Text(
              'Aucun document ajouté',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(docs.length, (i) {
              return Chip(
                avatar: const Icon(Icons.description,
                    size: 16, color: AppColors.primary),
                label: Text('Doc ${i + 1}'),
                onDeleted: () => onRemove(i),
              );
            }),
          ),
      ],
    );
  }
}

// =============================================================================
// Bloc IA générée
// =============================================================================
class _AiGenerationBlock extends StatelessWidget {
  final TextEditingController controller;
  final bool generating;
  final VoidCallback onGenerate;
  final bool validated;
  final ValueChanged<bool> onValidatedChanged;
  const _AiGenerationBlock({
    required this.controller,
    required this.generating,
    required this.onGenerate,
    required this.validated,
    required this.onValidatedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: generating ? null : onGenerate,
          icon: generating
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_awesome),
          label: Text(generating ? 'Génération...' : 'Générer le corrigé'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller,
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
          value: validated,
          onChanged: (v) => onValidatedChanged(v ?? false),
          title: const Text(
            'Je valide ce corrigé',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Aucune correction n\'est possible sans validation.'),
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ],
    );
  }
}
