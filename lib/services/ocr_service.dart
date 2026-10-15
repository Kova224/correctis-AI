import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/exam.dart';
import '../models/question.dart';
import '../utils/image_resizer.dart';
import '../utils/retry.dart';

/// Service OCR / extraction de questions à partir d'images de sujet.
///
/// ⚠️ Pas de fallback mock. Si l'Edge Function échoue, on lève une exception
/// avec un message clair. Un mock qui inventait des questions masquait des
/// vrais bugs et faisait noter l'IA selon un faux barème — c'est ce qui
/// causait le bug "l'IA note n'importe quelle copie".
class OcrService {
  static const _uuid = Uuid();

  SupabaseClient get _client => Supabase.instance.client;

  /// Extrait les exercices et leur barème d'un sujet importé.
  ///
  /// 1. Upload les images locales vers le bucket `subjects`
  /// 2. Appelle l'Edge Function `extract-questions` (Claude Vision)
  /// 3. Si échec à n'importe quel point → throw avec message explicite
  ///
  /// Retourne :
  ///   - `questions` : la liste structurée extraite par Claude
  ///   - `uploadedUrls` : les URLs publiques des images uploadées
  ///                       (À STOCKER dans `exam.subjectImages` pour que la
  ///                        correction IA puisse les revoir plus tard)
  Future<({List<Question> questions, List<String> uploadedUrls})>
      extractQuestionsFromSubject(
    List<String> imagePaths, {
    ExamLanguage language = ExamLanguage.french,
    ExamType examType = ExamType.general,
  }) async {
    // 1. Upload Storage — si ça échoue, on s'arrête net.
    final urls = await uploadSubjectImages(imagePaths);
    if (urls.isEmpty) {
      throw 'Aucune image valide à uploader.';
    }

    // 2. Appel à l'Edge Function pour structurer les questions
    final res = await _client.functions.invoke(
      'extract-questions',
      body: {
        'imageUrls': urls,
        'language': language.code,
        'examType': examType.code,
      },
    );

    if (res.status != null && (res.status! < 200 || res.status! >= 300)) {
      throw 'Extraction des questions échouée (HTTP ${res.status}). Vérifiez votre connexion et la clé Claude côté serveur.';
    }
    final data = res.data;
    if (data == null) {
      throw 'Extraction des questions : réponse vide du serveur.';
    }
    if (data is Map && data['error'] != null) {
      throw 'Extraction des questions : ${data['error']}';
    }
    if (data is! Map ||
        data['questions'] == null ||
        data['questions'] is! List) {
      throw 'Extraction des questions : format de réponse invalide.';
    }
    final questions = _parseQuestions(data['questions'] as List<dynamic>);
    if (questions.isEmpty) {
      throw 'Aucune question détectée dans le sujet. Vérifiez la qualité des photos.';
    }
    return (questions: questions, uploadedUrls: urls);
  }

  /// Upload les images du sujet vers Supabase Storage.
  /// Retourne les URLs publiques.
  /// ⚠️ Lève une exception si l'upload d'au moins une image échoue —
  /// PAS de chemin local conservé en fallback (l'IA ne pourrait jamais
  /// fetcher un chemin local et noterait à l'aveugle).
  Future<List<String>> uploadSubjectImages(List<String> paths) async {
    final userId = _client.auth.currentUser?.id ?? 'anon';
    final urls = <String>[];
    for (final path in paths) {
      // Déjà une URL → on la garde telle quelle
      if (path.startsWith('http://') || path.startsWith('https://')) {
        urls.add(path);
        continue;
      }
      // Resize si l'image dépasse 1800px (Anthropic limite à 2000px en
      // requête multi-images). Le helper gère aussi le ré-encodage JPG 85%.
      final resizedPath = await ImageResizer.resizeIfNeeded(path);

      final file = File(resizedPath);
      if (!file.existsSync()) {
        debugPrint('[uploadSubjectImages] fichier introuvable : $resizedPath');
        continue;
      }
      // L'extension finale du fichier (qui peut avoir changé après resize)
      final dotIdx = resizedPath.lastIndexOf('.');
      final ext = dotIdx >= 0 ? resizedPath.substring(dotIdx) : '.jpg';
      final remotePath = '$userId/${_uuid.v4()}$ext';
      try {
        await RetryHelper.run(
          () => _client.storage
              .from(SupabaseConfig.subjectsBucket)
              .upload(remotePath, file),
        );
        final url = _client.storage
            .from(SupabaseConfig.subjectsBucket)
            .getPublicUrl(remotePath);
        urls.add(url);
        debugPrint('[uploadSubjectImages] ✓ uploaded : $url');
      } catch (e) {
        debugPrint('[uploadSubjectImages] ✗ erreur upload : $e');
        throw 'Upload du sujet échoué : $e. Vérifiez votre connexion et que le bucket "subjects" existe et est public.';
      }
    }
    return urls;
  }

  /// Convertit la réponse JSON de l'Edge Function en List<Question>.
  List<Question> _parseQuestions(List<dynamic> raw) {
    return raw.map((q) {
      final map = q as Map<String, dynamic>;
      final subsRaw = (map['subQuestions'] as List<dynamic>?) ?? const [];
      final subs = subsRaw.map((s) {
        final sm = s as Map<String, dynamic>;
        return SubQuestion(
          label: sm['label'] as String? ?? '',
          statement: sm['statement'] as String? ?? '',
          points: (sm['points'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      return Question(
        label: map['label'] as String? ?? 'Question',
        statement: map['statement'] as String? ?? '',
        points: (map['points'] as num?)?.toDouble() ?? 0,
        subQuestions: subs,
      );
    }).toList();
  }
}
