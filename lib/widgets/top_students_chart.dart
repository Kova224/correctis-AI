import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class TopStudentBar {
  final String name;
  final double percent; // 0..100
  final double score;
  final double maxScore;
  final String? className;

  const TopStudentBar({
    required this.name,
    required this.percent,
    required this.score,
    required this.maxScore,
    this.className,
  });
}

/// Bar chart horizontal des meilleurs élèves — animation à l'apparition.
class TopStudentsChart extends StatelessWidget {
  final List<TopStudentBar> bars;
  final int maxItems;

  const TopStudentsChart({
    super.key,
    required this.bars,
    this.maxItems = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Row(
          children: [
            Icon(Icons.bar_chart, color: AppColors.textMuted),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Aucune donnée pour l\'instant — corrigez quelques copies pour voir vos meilleurs élèves.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final top = bars.take(maxItems).toList();
    return Column(
      children: [
        for (int i = 0; i < top.length; i++)
          _ChartBar(
            position: i + 1,
            data: top[i],
            highlight: i == 0,
          ),
      ],
    );
  }
}

class _ChartBar extends StatelessWidget {
  final int position;
  final TopStudentBar data;
  final bool highlight;

  const _ChartBar({
    required this.position,
    required this.data,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (data.percent / 100).clamp(0.0, 1.0);
    final barColor = highlight ? AppColors.accent : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // Position
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: highlight
                  ? AppColors.accent
                  : AppColors.primary.withValues(alpha: 0.1),
            ),
            child: Center(
              child: Text(
                '$position',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: highlight ? Colors.white : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Nom + classe + barre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      '${data.percent.toStringAsFixed(0)} %',
                      style: TextStyle(
                        color: barColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (data.className != null) ...[
                  Text(
                    data.className!,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      Container(
                        height: 8,
                        color: AppColors.surfaceMuted,
                      ),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: pct),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return FractionallySizedBox(
                            widthFactor: value,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    barColor,
                                    barColor.withValues(alpha: 0.7),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
