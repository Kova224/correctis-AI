import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Header sobre dark mode — V2 selon maquette Michel.
///
/// Anciennement bandeau bleu vif arrondi. Devient : fond void avec un léger
/// dégradé radial bleu en haut (style maquette), bordure inférieure subtile.
/// Pas d'arrondi exagéré — la maquette utilise des transitions discrètes.
class RoundedHeader extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsets contentPadding;
  final bool showBackButton;
  final VoidCallback? onBack;
  final List<Widget>? actions;

  /// Accent du dégradé (par défaut bleu primary).
  /// Permet de teinter les headers selon le contexte (vert pour prof, violet
  /// pour admin, etc.).
  final Color? accentColor;

  const RoundedHeader({
    super.key,
    required this.child,
    this.height = 200,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
    this.showBackButton = false,
    this.onBack,
    this.actions,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final accent = accentColor ?? AppColors.primary;

    return Container(
      width: double.infinity,
      height: height + topInset,
      decoration: BoxDecoration(
        // Dégradé radial subtil — la maquette utilise ce pattern pour
        // donner du relief sans bandeau coloré agressif.
        gradient: RadialGradient(
          center: const Alignment(0, -1.2),
          radius: 1.5,
          colors: [
            accent.withValues(alpha: 0.15),
            AppColors.voidBg,
          ],
          stops: const [0.0, 0.7],
        ),
        // Bordure inférieure subtile pour séparer du contenu
        border: const Border(
          bottom: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
      ),
      padding: EdgeInsets.only(top: topInset),
      child: Column(
        children: [
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

/// Bouton circulaire subtil — fond card avec bordure très discrète.
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
      color: AppColors.card,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.borderSubtle, width: 1),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: iconColor ?? AppColors.textPrimary,
            size: 16,
          ),
        ),
      ),
    );
  }
}

/// Bouton circulaire utilitaire — pour les actions du header.
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
        color: AppColors.card,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.borderSubtle, width: 1),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child:
                Icon(icon, color: AppColors.textPrimary, size: 16),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
