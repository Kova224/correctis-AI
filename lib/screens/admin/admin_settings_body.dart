import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/establishment.dart';
import '../../services/auth_service.dart';
import '../../services/establishment_service.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../profile/delete_account_screen.dart';
import '../profile/support_screen.dart';
import 'admin_credits_screen.dart';
import 'admin_pedagogy_config_screen.dart';

/// A5 — Paramètres établissement (vue Admin).
class AdminSettingsBody extends StatefulWidget {
  const AdminSettingsBody({super.key});

  @override
  State<AdminSettingsBody> createState() => _AdminSettingsBodyState();
}

class _AdminSettingsBodyState extends State<AdminSettingsBody> {
  /// Met à jour les préférences notifications/sécurité dans la config.
  Future<void> _updatePrefs(
    BuildContext context,
    EstablishmentNotificationPrefs Function(
            EstablishmentNotificationPrefs old)
        mutator,
  ) async {
    final svc = context.read<EstablishmentService>();
    final cfg = svc.currentEstablishment?.config ??
        const EstablishmentConfig();
    final newPrefs = mutator(cfg.notifications);
    try {
      await svc.updateConfig(cfg.copyWith(notifications: newPrefs));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur : $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<EstablishmentService>();
    final school = svc.currentEstablishment;
    final teacherCount = svc.members.where((m) => m.isTeacher).length;
    final classes = <String>{};
    for (final m in svc.members) {
      classes.addAll(m.classes);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ━━━━━━ HEADER ━━━━━━
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
            'Établissement',
            style: AppFonts.fraunces(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 18),

          // ━━━━━━ ÉCOLE CARD ━━━━━━
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.adminPrimary.withValues(alpha: 0.1),
                  AppColors.primary.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(
                color: AppColors.adminPrimary.withValues(alpha: 0.25),
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.adminGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        school?.name ?? 'Aucun établissement',
                        style: AppFonts.fraunces(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        school == null
                            ? '—'
                            : '${school.planLabel}${school.city != null ? " · ${school.city}" : ""}',
                        style: AppFonts.sans(
                          fontSize: 11,
                          color: AppColors.adminPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$teacherCount enseignant${teacherCount != 1 ? "s" : ""} · ${classes.length} classe${classes.length != 1 ? "s" : ""}',
                        style: AppFonts.mono(
                          fontSize: 9.5,
                          color: AppColors.textMuted,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // ━━━━━━ PÉDAGOGIE ━━━━━━
          _sectionLabel('PÉDAGOGIE'),
          _navRow(
            icon: Icons.event_note_outlined,
            label: 'Trimestres & coefficients',
            sub: school?.config.hasTerms == true
                ? '${school!.config.terms.length} période${school.config.terms.length > 1 ? "s" : ""} · ${school.config.coefficients.length} matière${school.config.coefficients.length > 1 ? "s" : ""}'
                : 'Non configurés',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AdminPedagogyConfigScreen(),
              ),
            ),
          ),

          const SizedBox(height: 22),

          // ━━━━━━ CONFIDENTIALITÉ ━━━━━━
          _sectionLabel('CONFIDENTIALITÉ & SÉCURITÉ'),
          _toggleRow(
            icon: Icons.shield_outlined,
            label: 'Confidentialité stricte',
            sub: 'Admin voit les notes, pas les corrections sans accord prof',
            value: school?.config.notifications.confidentialityStrict ?? true,
            onChanged: (v) => _updatePrefs(
              context,
              (p) => p.copyWith(confidentialityStrict: v),
            ),
          ),
          _toggleRow(
            icon: Icons.history_rounded,
            label: 'Audit log horodaté',
            sub: 'Toute modification de note est tracée et non effaçable',
            value: school?.config.notifications.auditLog ?? true,
            onChanged: (v) => _updatePrefs(
              context,
              (p) => p.copyWith(auditLog: v),
            ),
          ),

          const SizedBox(height: 22),

          // ━━━━━━ NOTIFICATIONS ━━━━━━
          _sectionLabel('NOTIFICATIONS'),
          _toggleRow(
            icon: Icons.notifications_outlined,
            label: 'Alertes pédagogiques',
            sub: 'Recevoir les alertes IA sur les classes en difficulté',
            value: school?.config.notifications.alerts ?? true,
            onChanged: (v) => _updatePrefs(
              context,
              (p) => p.copyWith(alerts: v),
            ),
          ),
          _toggleRow(
            icon: Icons.mark_email_read_outlined,
            label: 'Rappels invitations',
            sub: 'Recevoir un rappel pour les invitations non acceptées',
            value:
                school?.config.notifications.invitationsReminders ?? true,
            onChanged: (v) => _updatePrefs(
              context,
              (p) => p.copyWith(invitationsReminders: v),
            ),
          ),
          _toggleRow(
            icon: Icons.analytics_outlined,
            label: 'Statistiques anonymes',
            sub: 'Partager des stats anonymes pour améliorer Correctis',
            value: school?.config.notifications.anonymousStats ?? false,
            onChanged: (v) => _updatePrefs(
              context,
              (p) => p.copyWith(anonymousStats: v),
            ),
          ),

          const SizedBox(height: 22),

          // ━━━━━━ CRÉDITS (pay-as-you-go, grille v5 — sans abonnement) ━━━━━━
          _sectionLabel('CRÉDITS'),
          _navRow(
            icon: Icons.credit_card_outlined,
            label: 'Crédits de l\'établissement',
            sub: 'Packs, pool, quotas profs et historique des achats',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminCreditsScreen()),
            ),
          ),

          const SizedBox(height: 22),

          _sectionLabel('SUPPORT'),
          _navRow(
            icon: Icons.help_outline_rounded,
            label: 'Centre d\'aide',
            sub: 'FAQ + tutoriels',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            ),
          ),
          _navRow(
            icon: Icons.email_outlined,
            label: 'Contacter le support',
            sub: 'E-mail, WhatsApp, téléphone',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            ),
          ),

          const SizedBox(height: 22),

          // ━━━━━━ DÉCONNEXION ━━━━━━
          _sectionLabel('COMPTE'),
          Material(
            color: AppColors.danger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => _confirmLogout(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.25),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      size: 20,
                      color: AppColors.danger,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Se déconnecter',
                        style: AppFonts.sans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Suppression du compte (exigence Google Play). Bloquée côté serveur
          // pour le propriétaire / seul admin d'une école : l'écran l'explique.
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
            ),
            icon: const Icon(
              Icons.person_remove_outlined,
              size: 18,
              color: AppColors.textMuted,
            ),
            label: Text(
              'Supprimer mon compte',
              style: AppFonts.sans(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(
          'Se déconnecter ?',
          style: AppFonts.fraunces(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Vous reviendrez à l\'écran de connexion. '
          'Vos données restent sauvegardées.',
          style: AppFonts.sans(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Déconnexion',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AuthService>().logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: AppFonts.mono(
          fontSize: 10,
          color: AppColors.textMuted,
          letterSpacing: 2,
        ),
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String label,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.adminPrimary),
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
                activeColor: AppColors.adminPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required String label,
    required String sub,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.adminPrimary),
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
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
