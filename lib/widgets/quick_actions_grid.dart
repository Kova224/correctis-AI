import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class QuickAction {
  final IconData icon;
  final String label;
  final Color color;     // couleur du fond pastel
  final Color iconColor; // couleur de l'icône (saturée)
  final VoidCallback onTap;
  final String? badge;   // ex: "3 en attente"

  const QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.iconColor,
    required this.onTap,
    this.badge,
  });
}

/// Grille 2×2 d'actions rapides avec icônes colorées (style dashboard moderne).
class QuickActionsGrid extends StatelessWidget {
  final List<QuickAction> actions;
  const QuickActionsGrid({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: actions.length,
      itemBuilder: (context, i) => _QuickActionTile(action: actions[i]),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final QuickAction action;
  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Icône colorée
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: action.color,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: action.iconColor.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(action.icon, color: action.iconColor, size: 22),
                  ),
                  // Label + chevron
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          action.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: AppColors.textMuted),
                    ],
                  ),
                ],
              ),
              // Badge (optionnel)
              if (action.badge != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: action.iconColor,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      action.badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
