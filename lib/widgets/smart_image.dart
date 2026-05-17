import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Affiche une image quelle que soit sa source :
/// - URL HTTP/HTTPS → `Image.network`
/// - Chemin local (file:///, /sdcard/, etc.) → `Image.file`
/// - Chemin vide ou fichier introuvable → placeholder
class SmartImage extends StatelessWidget {
  final String? path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorPlaceholder;

  const SmartImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorPlaceholder,
  });

  bool get _isRemote => path != null && path!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    if (path == null || path!.isEmpty) {
      return _placeholder();
    }
    if (_isRemote) {
      return Image.network(
        path!,
        fit: fit,
        width: width,
        height: height,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _loading();
        },
        errorBuilder: (_, __, ___) => _error(),
      );
    }
    final file = File(path!);
    if (!file.existsSync()) return _error();
    return Image.file(
      file,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => _error(),
    );
  }

  Widget _placeholder() =>
      placeholder ?? _defaultBox(Icons.image_outlined);

  Widget _error() => errorPlaceholder ?? _defaultBox(Icons.broken_image_outlined);

  Widget _loading() => Container(
        width: width,
        height: height,
        color: AppColors.surfaceMuted,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );

  Widget _defaultBox(IconData icon) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceMuted,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.textMuted, size: 32),
      );
}
