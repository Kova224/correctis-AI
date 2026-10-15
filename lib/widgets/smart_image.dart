import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/private_storage.dart';

/// Affiche une image quelle que soit sa source :
/// - URL HTTP/HTTPS → `Image.network` (lien signé pour les copies d'élèves,
///   le bucket `copies` étant privé — cf. [PrivateStorage])
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
      return _RemoteImage(
        url: path!,
        fit: fit,
        width: width,
        height: height,
        loading: _loading(),
        error: _error(),
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

/// Image distante : résout d'abord un lien signé si l'URL pointe vers le
/// bucket privé `copies`, puis affiche l'image.
class _RemoteImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget loading;
  final Widget error;

  const _RemoteImage({
    required this.url,
    required this.fit,
    required this.width,
    required this.height,
    required this.loading,
    required this.error,
  });

  @override
  State<_RemoteImage> createState() => _RemoteImageState();
}

class _RemoteImageState extends State<_RemoteImage> {
  late Future<String> _resolved;

  @override
  void initState() {
    super.initState();
    _resolved = PrivateStorage.resolve(widget.url);
  }

  @override
  void didUpdateWidget(covariant _RemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _resolved = PrivateStorage.resolve(widget.url);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _resolved,
      builder: (context, snap) {
        if (snap.hasError) return widget.error;
        if (!snap.hasData) return widget.loading;
        return Image.network(
          snap.data!,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return widget.loading;
          },
          errorBuilder: (_, __, ___) => widget.error,
        );
      },
    );
  }
}
