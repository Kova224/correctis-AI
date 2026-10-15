import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../admin/admin_widgets.dart';

/// Écran de gestion des préférences de notifications.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.voidBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.7),
            radius: 1.4,
            colors: [Color(0xFF120A2E), AppColors.voidBg],
            stops: [0.0, 0.75],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AdminBackButton(
                    onTap: () => Navigator.maybePop(context)),
                const SizedBox(height: 18),
                Text(
                  'PARAMÈTRES',
                  style: AppFonts.mono(
                    fontSize: 10,
                    color: AppColors.textMuted,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Notifications',
                  style: AppFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Choisissez quels événements vous souhaitez recevoir.',
                  style: AppFonts.sans(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 24),
                Consumer<NotificationService>(
                  builder: (context, svc, _) {
                    final p = svc.prefs;
                    return Column(
                      children: [
                        _toggle(
                          icon: Icons.task_alt_rounded,
                          label: 'Copies corrigées',
                          sub: 'Recevoir une notification quand une correction est prête.',
                          value: p.copiesReady,
                          onChanged: svc.setCopiesReady,
                        ),
                        _toggle(
                          icon: Icons.mark_email_read_outlined,
                          label: 'Invitations',
                          sub: 'Rappels pour les invitations envoyées non acceptées.',
                          value: p.invitations,
                          onChanged: svc.setInvitations,
                        ),
                        _toggle(
                          icon: Icons.warning_amber_rounded,
                          label: 'Crédits faibles',
                          sub: 'Alerte quand il vous reste 3 crédits ou moins.',
                          value: p.quotaWarning,
                          onChanged: svc.setQuotaWarning,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.primaryLight,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Les notifications sont envoyées localement par votre téléphone. '
                          'Aucune donnée n\'est envoyée vers un serveur de notifications.',
                          style: AppFonts.sans(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggle({
    required IconData icon,
    required String label,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppFonts.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: AppFonts.sans(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeColor: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
