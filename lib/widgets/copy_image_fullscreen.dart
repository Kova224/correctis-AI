import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'smart_image.dart';

/// Vue plein écran des pages d'une copie avec swipe horizontal et pinch-zoom.
///
/// Utilisé depuis :
///   - StudentCopyDetailScreen (tap sur une thumbnail "Pages scannées")
///   - IllegibleZonesScreen (viewer inline → tap → plein écran)
///
/// Zoom jusqu'à 6x, swipe entre pages, appuie sur back pour fermer.
class CopyImageFullscreen extends StatefulWidget {
  final List<String> pages;
  final int initialPage;

  const CopyImageFullscreen({
    super.key,
    required this.pages,
    this.initialPage = 0,
  });

  /// Helper : ouvre la vue plein écran depuis n'importe où.
  static Future<void> open(
    BuildContext context, {
    required List<String> pages,
    int initialPage = 0,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CopyImageFullscreen(
          pages: pages,
          initialPage: initialPage,
        ),
      ),
    );
  }

  @override
  State<CopyImageFullscreen> createState() => _CopyImageFullscreenState();
}

class _CopyImageFullscreenState extends State<CopyImageFullscreen> {
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
