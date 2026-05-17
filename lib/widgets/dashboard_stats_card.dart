import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DashboardStats {
  final int examsCount;
  final int copiesGraded;
  final int copiesTotal;
  final double averagePercent;

  const DashboardStats({
    required this.examsCount,
    required this.copiesGraded,
    required this.copiesTotal,
    required this.averagePercent,
  });

  double get progressRatio =>
      copiesTotal == 0 ? 0 : copiesGraded / copiesTotal;
}

/// Carte de stats horizontale (inspirée du design CrowdFund) :
/// 3 chiffres côte à côte + barre de progression en bas.
class DashboardStatsCard extends StatelessWidget {
  final DashboardStats stats;
  const DashboardStatsCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatColumn(
                  value: '${(stats.progressRatio * 100).toStringAsFixed(0)}%',
                  label: 'Progression',
                  color: AppColors.primary,
                  large: true,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: AppColors.divider,
              ),
              Expanded(
                child: _StatColumn(
                  value: '${stats.copiesGraded}',
                  subValue: '/${stats.copiesTotal}',
                  label: 'Copies',
                  color: AppColors.accentDark,
                  large: true,
                ),
              ),
              Container(
                width: 1,
                height: 42,
                color: AppColors.divider,
              ),
              Expanded(
                child: _StatColumn(
                  value: stats.examsCount.toString(),
                  label: 'Examens',
                  color: AppColors.warning,
                  large: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Barre de progression globale animée
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              children: [
                Container(
                  height: 6,
                  color: AppColors.surfaceMuted,
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: stats.progressRatio),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) {
                    return FractionallySizedBox(
                      widthFactor: v,
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            stats.averagePercent.isNaN || stats.averagePercent == 0
                ? 'Moyenne : —'
                : 'Moyenne générale : ${stats.averagePercent.toStringAsFixed(1)} %',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String value;
  final String? subValue;
  final String label;
  final Color color;
  final bool large;
  const _StatColumn({
    required this.value,
    this.subValue,
    required this.label,
    required this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            text: value,
            style: TextStyle(
              fontSize: large ? 22 : 18,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.3,
              height: 1.1,
            ),
            children: [
              if (subValue != null)
                TextSpan(
                  text: subValue,
                  style: TextStyle(
                    fontSize: large ? 14 : 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
