import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../theme/app_theme.dart';

/// C1 renforcé (Michel) — Caméra custom en mode "burst / rafale".
///
/// Le prof appuie **une seule fois** sur "Scanner" depuis ScanSessionScreen.
/// Cet écran s'ouvre : preview live + gros bouton central.
/// À chaque clic sur le bouton, la photo est capturée et sauvegardée
/// **sans passer par un preview de confirmation "OK/Retry"** — la caméra
/// reste active, prête pour la prochaine page.
///
/// Le prof enchaîne 5-10 pages en quelques secondes puis appuie sur "OK"
/// (compteur en haut à droite) pour revenir à la ScanSessionScreen avec
/// toutes les pages capturées.
///
/// Retourne : List<String> (chemins locaux des photos capturées).
class BurstCameraScreen extends StatefulWidget {
  const BurstCameraScreen({super.key});

  @override
  State<BurstCameraScreen> createState() => _BurstCameraScreenState();
}

class _BurstCameraScreenState extends State<BurstCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  final List<String> _capturedPaths = [];
  bool _capturing = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = 'Aucune caméra détectée sur ce téléphone.');
        return;
      }
      // Prend la caméra arrière (back) par défaut
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        rear,
        ResolutionPreset.high, // ~1280x720 — largement suffisant pour l'IA
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _initFuture = _controller!.initialize();
      await _initFuture;
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      setState(() => _initError = 'Erreur caméra : $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final xfile = await ctrl.takePicture();
      // Copie dans un dossier temp propre (image_picker style)
      final tempDir = await getTemporaryDirectory();
      final fileName =
          'burst_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dest = File('${tempDir.path}/$fileName');
      await File(xfile.path).copy(dest.path);
      _capturedPaths.add(dest.path);
      // Feedback flash blanc court pour signaler la capture
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur capture : $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _removeLast() {
    if (_capturedPaths.isEmpty) return;
    final last = _capturedPaths.removeLast();
    try {
      File(last).deleteSync();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _finish() {
    Navigator.of(context).pop(_capturedPaths);
  }

  void _cancel() {
    // Supprime les fichiers capturés
    for (final p in _capturedPaths) {
      try {
        File(p).deleteSync();
      } catch (_) {}
    }
    Navigator.of(context).pop(<String>[]);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _cancel();
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _initError != null
              ? _errorView()
              : _controller == null || !_controller!.value.isInitialized
                  ? _loadingView()
                  : Stack(
                      children: [
                        // ─── Preview caméra plein écran ───
                        Positioned.fill(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _controller!.value.previewSize?.height ??
                                  1,
                              height:
                                  _controller!.value.previewSize?.width ?? 1,
                              child: CameraPreview(_controller!),
                            ),
                          ),
                        ),
                        // ─── Header (Annuler + compteur) ───
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _topBar(),
                        ),
                        // ─── Flash blanc pendant capture ───
                        if (_capturing)
                          Positioned.fill(
                            child: Container(
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        // ─── Bouton central + preview miniature ───
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: _bottomBar(),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_rounded,
                color: Colors.white70, size: 48),
            const SizedBox(height: 14),
            Text(
              _initError ?? 'Caméra indisponible',
              textAlign: TextAlign.center,
              style: AppFonts.sans(fontSize: 13, color: Colors.white),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70),
              ),
              onPressed: () => Navigator.of(context).pop(<String>[]),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingView() {
    return const Center(
      child: SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation(Colors.white),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _cancel,
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_capturedPaths.length} page${_capturedPaths.length != 1 ? "s" : ""}',
              style: AppFonts.mono(
                fontSize: 12,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          if (_capturedPaths.isNotEmpty)
            TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.profPrimary,
              ),
              child: Text(
                'OK',
                style: AppFonts.mono(
                  fontSize: 14,
                  color: AppColors.profPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.75),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Miniature dernière capture (48x64)
          SizedBox(
            width: 48,
            height: 64,
            child: _capturedPaths.isEmpty
                ? const SizedBox.shrink()
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(_capturedPaths.last),
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const Spacer(),
          // Bouton shutter géant
          GestureDetector(
            onTap: _capture,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Center(
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Bouton "supprimer dernière"
          SizedBox(
            width: 48,
            height: 64,
            child: _capturedPaths.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    onPressed: _removeLast,
                    icon: const Icon(
                      Icons.replay_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                    tooltip: 'Reprendre la dernière',
                  ),
          ),
        ],
      ),
    );
  }
}
