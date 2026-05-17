import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/greeting.dart';

/// Affiche une bannière de salutation chaleureuse en haut de l'écran.
/// Utilise un Overlay pour ne pas perturber le layout, animation slide+fade,
/// auto-dismiss après [duration].
class GreetingBanner {
  static OverlayEntry? _current;

  /// Affiche la bannière. Appeler depuis un postFrameCallback dans le build du Home.
  static void show(
    BuildContext context, {
    required String displayName,
    Duration duration = const Duration(milliseconds: 4500),
  }) {
    // Évite les doublons si déjà affichée
    _current?.remove();
    _current = null;

    final greeting = Greeting.forUser(displayName: displayName);
    final overlay = Overlay.of(context);

    final entry = OverlayEntry(
      builder: (_) => _GreetingBannerWidget(
        greeting: greeting,
        autoDismissAfter: duration,
        onDismissed: () {
          _current?.remove();
          _current = null;
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _GreetingBannerWidget extends StatefulWidget {
  final Greeting greeting;
  final Duration autoDismissAfter;
  final VoidCallback onDismissed;

  const _GreetingBannerWidget({
    required this.greeting,
    required this.autoDismissAfter,
    required this.onDismissed,
  });

  @override
  State<_GreetingBannerWidget> createState() => _GreetingBannerWidgetState();
}

class _GreetingBannerWidgetState extends State<_GreetingBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

    _ctrl.forward();
    Future.delayed(widget.autoDismissAfter, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    if (!mounted) return;
    widget.onDismissed();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      top: mq.padding.top + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.accent, AppColors.accentDark],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.greeting.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.greeting.fullText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.greeting.jovialPhrase,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.95),
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _dismiss,
                      icon: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
