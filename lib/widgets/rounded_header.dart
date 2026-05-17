import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Header bleu arrondi (style CrowdFund) — coins arrondis en bas.
/// Hauteur = `height` (au-dessus du status bar). La hauteur totale rendue
/// inclut automatiquement le status bar (SafeArea).
class RoundedHeader extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsets contentPadding;
  final bool showBackButton;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  const RoundedHeader({
    super.key,
    required this.child,
    this.height = 220,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
    this.showBackButton = false,
    this.onBack,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      height: height + topInset,
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      padding: EdgeInsets.only(top: topInset),
      child: Column(
        children: [
          // Barre du haut — flèche retour à gauche, actions à droite
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (showBackButton)
                    _CircleIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onPressed:
                          onBack ?? () => Navigator.of(context).maybePop(),
                    )
                  else
                    const SizedBox(width: 40),
                  const Spacer(),
                  if (actions != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!,
                    ),
                ],
              ),
            ),
          ),
          // Contenu principal — pleine hauteur disponible (bornée)
          Expanded(
            child: Padding(
              padding: contentPadding,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton circulaire semi-transparent — pour la flèche retour et autres actions.
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? iconColor;

  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.18),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: iconColor ?? Colors.white,
            size: 18,
          ),
        ),
      ),
    );
  }
}

/// Bouton circulaire utilitaire (utilisable depuis les `actions:` du header).
class HeaderCircleAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  const HeaderCircleAction({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final btn = Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
