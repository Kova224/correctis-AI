import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'admin_models.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// COMPOSANTS PARTAGÉS — VUE ADMIN
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Back button circulaire (utilisé par tous les écrans admin pushed).
class AdminBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const AdminBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.borderSubtle),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 14,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Avatar gradient avec initiales — différents gradients selon l'`avatarKey`.
class AdminAvatar extends StatelessWidget {
  final String initials;
  final String avatarKey;
  final double size;
  final bool withBorder;
  const AdminAvatar({
    super.key,
    required this.initials,
    required this.avatarKey,
    this.size = 40,
    this.withBorder = false,
  });

  Gradient get _gradient {
    switch (avatarKey) {
      case 'green':
        return const LinearGradient(
          colors: [Color(0xFF059669), Color(0xFF0891B2)],
        );
      case 'blue':
        return const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF06B6D4)],
        );
      case 'purple':
        return const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF2563EB)],
        );
      case 'amber':
        return const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFEF4444)],
        );
      default:
        return AppColors.adminGradient;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: _gradient,
        shape: BoxShape.circle,
        border: withBorder
            ? Border.all(
                color: AppColors.adminPrimary.withValues(alpha: 0.3),
                width: 2,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: AppFonts.sans(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// KPI Card (Dashboard A1).
class AdminKpiCard extends StatelessWidget {
  final AdminKpi kpi;
  final Color color;
  const AdminKpiCard({super.key, required this.kpi, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Value + sub
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                kpi.value,
                style: AppFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  kpi.sub,
                  style: AppFonts.sans(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            kpi.deltaText,
            style: AppFonts.sans(
              fontSize: 9.5,
              color: kpi.isPositive
                  ? AppColors.profPrimary
                  : AppColors.warning,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            kpi.label,
            style: AppFonts.mono(
              fontSize: 8.5,
              color: AppColors.textMuted,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Alerte (info, warning, error).
class AdminAlertCard extends StatelessWidget {
  final AdminAlert alert;
  const AdminAlertCard({super.key, required this.alert});

  Color get _color {
    switch (alert.severity) {
      case AdminAlertSeverity.error:
        return AppColors.danger;
      case AdminAlertSeverity.warning:
        return AppColors.warning;
      case AdminAlertSeverity.info:
        return AppColors.primaryLight;
    }
  }

  IconData get _icon {
    switch (alert.severity) {
      case AdminAlertSeverity.error:
        return Icons.error_outline_rounded;
      case AdminAlertSeverity.warning:
        return Icons.warning_amber_rounded;
      case AdminAlertSeverity.info:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.08),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 18, color: _color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alert.message,
              style: AppFonts.sans(
                fontSize: 12,
                color: _color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ligne de classe (Dashboard).
class AdminClassRow extends StatelessWidget {
  final AdminClass classe;
  const AdminClassRow({super.key, required this.classe});

  Color get _color {
    switch (classe.color) {
      case 'green':
        return AppColors.profPrimary;
      case 'amber':
        return AppColors.warning;
      case 'blue':
      default:
        return AppColors.primaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ratio = (classe.avg / 20).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classe.name,
                  style: AppFonts.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  classe.sub,
                  style: AppFonts.sans(
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                backgroundColor: const Color(0x14FFFFFF),
                valueColor: AlwaysStoppedAnimation(_color),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            classe.avg.toStringAsFixed(1),
            style: AppFonts.fraunces(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill filtre actif/inactif.
class AdminFilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const AdminFilterPill({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        active ? AppColors.adminPrimary : AppColors.textMuted;
    return Material(
      color: active
          ? AppColors.adminPrimary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            border: Border.all(
              color: active
                  ? AppColors.adminPrimary.withValues(alpha: 0.35)
                  : AppColors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label.toUpperCase(),
            style: AppFonts.mono(
              fontSize: 9,
              color: color,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton gradient violet pleine largeur (style admin).
class AdminGradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  const AdminGradientButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.adminGradient,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: AppColors.adminPrimary.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: AppFonts.mono(
                    fontSize: 12,
                    color: Colors.white,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
