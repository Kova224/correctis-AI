import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Helper de redimensionnement d'images.
///
/// CONTEXTE — Anthropic Claude vision limite chaque image à :
///   • 2000 pixels (largeur OU hauteur) quand la requête contient plusieurs images
///   • 8000 pixels (largeur OU hauteur) pour une requête mono-image
///
/// Nos requêtes contiennent toujours plusieurs images (sujet + corrigé + copie).
/// On force donc un redimensionnement à 1800px AVANT l'upload.
///
/// ⚡ PERFORMANCE :
/// Le décodage et le resize d'images sont des opérations CPU-INTENSIVES qui
/// BLOQUERAIENT le thread principal pendant 2-10 secondes par image. C'est
/// pour ça que "Terminer cette copie" prenait 12+ secondes.
///
/// SOLUTION : on délègue tout le travail lourd à un ISOLATE séparé via
/// `compute()`. Le main thread reste fluide pour l'UI pendant le traitement.
class ImageResizer {
  // C4 (Sprint 3, itération 2) — Réduction 1400 → 1200px pour speed max.
  // Anthropic Claude Haiku traite les images ~50 % plus vite à 1200px
  // qu'à 1800px, sans perte notable pour la lecture manuscrite.
  // Les caractères font ~35-50px à 1200px, restent lisibles pour l'IA.
  // Combiné au prompt caching, viser < 90 s / copie (au lieu de 4 min).
  static const int _maxDimension = 1200;
  static const int _jpgQuality = 80;
  static const _uuid = Uuid();

  /// Formats supportés par la lib `image`. Les autres (PDF, DOCX) sont
  /// retournés tels quels.
  static const _supportedExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};

  /// Redimensionne le fichier si nécessaire.
  /// Retourne le chemin du fichier redimensionné (ou le chemin d'origine
  /// si pas besoin / format non-image).
  ///
  /// ⚡ Le travail CPU se fait dans un ISOLATE séparé → ne bloque PAS l'UI.
  static Future<String> resizeIfNeeded(String inputPath) async {
    final ext = p.extension(inputPath).toLowerCase().replaceFirst('.', '');

    // PDF / autre format non-image → ne touche pas
    if (!_supportedExts.contains(ext)) {
      debugPrint('[ImageResizer] skip non-image : $inputPath (.$ext)');
      return inputPath;
    }

    final file = File(inputPath);
    if (!file.existsSync()) {
      debugPrint('[ImageResizer] fichier inexistant : $inputPath');
      return inputPath;
    }

    try {
      // Récupère le dossier temp sur le main thread (platform channel)
      final tempDir = await getTemporaryDirectory();
      final outputPath = p.join(
        tempDir.path,
        'resized_${_uuid.v4()}.jpg',
      );

      // Délègue à l'isolate — décodage + resize + encodage JPG en arrière-plan
      final result = await compute(
        _resizeInIsolate,
        _ResizeArgs(
          inputPath: inputPath,
          outputPath: outputPath,
          maxDimension: _maxDimension,
          jpgQuality: _jpgQuality,
        ),
      );

      if (result.success) {
        debugPrint(
            '[ImageResizer] ✓ ${result.originalW}x${result.originalH} → ${result.newW}x${result.newH} (${result.outputSizeKb} KB) → $outputPath');
        return outputPath;
      } else {
        // Pas besoin de resize OU erreur dans l'isolate → garde l'original
        if (result.skipReason != null) {
          debugPrint('[ImageResizer] ${result.skipReason}');
        }
        return inputPath;
      }
    } catch (e) {
      debugPrint('[ImageResizer] erreur compute : $e (fallback chemin original)');
      return inputPath;
    }
  }

  /// Redimensionne en lot.
  static Future<List<String>> resizeAllIfNeeded(List<String> paths) async {
    final out = <String>[];
    for (final path in paths) {
      out.add(await resizeIfNeeded(path));
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// ISOLATE — travail CPU-bound exécuté en arrière-plan
// ─────────────────────────────────────────────────────────────────────────

/// Arguments envoyés à l'isolate. Doit être sérialisable (champs primitifs).
class _ResizeArgs {
  final String inputPath;
  final String outputPath;
  final int maxDimension;
  final int jpgQuality;
  const _ResizeArgs({
    required this.inputPath,
    required this.outputPath,
    required this.maxDimension,
    required this.jpgQuality,
  });
}

/// Résultat du resize côté isolate.
class _ResizeResult {
  final bool success;
  final int originalW;
  final int originalH;
  final int newW;
  final int newH;
  final int outputSizeKb;
  final String? skipReason;
  const _ResizeResult({
    required this.success,
    this.originalW = 0,
    this.originalH = 0,
    this.newW = 0,
    this.newH = 0,
    this.outputSizeKb = 0,
    this.skipReason,
  });
}

/// Fonction top-level appelée dans un isolate par `compute()`.
/// Effectue tout le travail lourd : décodage, resize, encodage, écriture.
_ResizeResult _resizeInIsolate(_ResizeArgs args) {
  try {
    final inputBytes = File(args.inputPath).readAsBytesSync();
    final original = img.decodeImage(inputBytes);
    if (original == null) {
      return const _ResizeResult(
        success: false,
        skipReason: 'décodage impossible',
      );
    }

    final w = original.width;
    final h = original.height;

    // Déjà assez petite → on garde l'original (gain de temps)
    if (w <= args.maxDimension && h <= args.maxDimension) {
      return _ResizeResult(
        success: false,
        originalW: w,
        originalH: h,
        skipReason: 'déjà ≤ ${args.maxDimension}px',
      );
    }

    // Calcule les nouvelles dimensions proportionnelles
    final ratio =
        w > h ? args.maxDimension / w : args.maxDimension / h;
    final newW = (w * ratio).round();
    final newH = (h * ratio).round();

    // Resize (algorithme average = bon compromis qualité/vitesse)
    final resized = img.copyResize(
      original,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.average,
    );

    // Ré-encode en JPG qualité 85
    final jpgBytes = img.encodeJpg(resized, quality: args.jpgQuality);

    // Écrit sur disque
    File(args.outputPath).writeAsBytesSync(jpgBytes);

    return _ResizeResult(
      success: true,
      originalW: w,
      originalH: h,
      newW: newW,
      newH: newH,
      outputSizeKb: jpgBytes.length ~/ 1024,
    );
  } catch (e) {
    return _ResizeResult(
      success: false,
      skipReason: 'isolate error : $e',
    );
  }
}
