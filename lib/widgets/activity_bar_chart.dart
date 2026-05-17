import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class DayActivity {
  final String label;     // L, M, M, J, V, S, D
  final int graded;       // copies corrigées ce jour
  final int scanned;      // copies scannées ce jour
  final bool isToday;
  const DayActivity({
    required this.label,
    required this.graded,
    required this.scanned,
    this.isToday = false,
  });
}

/// Bar chart hebdomadaire — copies corrigées vs scannées par jour.
class ActivityBarChart extends StatelessWidget {
  final List<DayActivity> days;
  final String title;
  final String subtitle;

  const ActivityBarChart({
    super.key,
    required this.days,
    this.title = 'Activité de la semaine',
    this.subtitle = 'Corrigées vs scannées',
  });

  @override
  Widget build(BuildContext context) {
    final maxV = days
        .map((d) => math.max(d.graded, d.scanned))
        .fold<int>(1, (a, b) => math.max(a, b));

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header avec titre et légende
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _LegendDot(color: AppColors.primary, label: 'Corrigées'),
                  const SizedBox(width: 8),
                  _LegendDot(color: AppColors.accent, label: 'Scannées'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Bars
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: days.map((d) {
                return Expanded(
                  child: _BarGroup(day: d, maxValue: maxV),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _BarGroup extends StatelessWidget {
  final DayActivity day;
  final int maxValue;
  const _BarGroup({required this.day, required this.maxValue});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Valeur au-dessus de la plus haute barre
          if (day.graded > 0 || day.scanned > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${math.max(day.graded, day.scanned)}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: day.isToday ? AppColors.primary : AppColors.textMuted,
                ),
              ),
            ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _AnimatedBar(
                    value: day.graded.toDouble(),
                    maxValue: maxValue.toDouble(),
                    color: AppColors.primary,
                    delay: 0,
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: _AnimatedBar(
                    value: day.scanned.toDouble(),
                    maxValue: maxValue.toDouble(),
                    color: AppColors.accent,
                    delay: 100,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: day.isToday
                  ? AppColors.primary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              day.label,
              style: TextStyle(
                fontSize: 11,
                color: day.isToday ? Colors.white : AppColors.textSecondary,
                fontWeight: day.isToday ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedBar extends StatelessWidget {
  final double value;
  final double maxValue;
  final Color color;
  final int delay;

  const _AnimatedBar({
    required this.value,
    required this.maxValue,
    required this.color,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = maxValue == 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: ratio),
      duration: Duration(milliseconds: 800 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return FractionallySizedBox(
          heightFactor: v == 0 ? 0.02 : v,
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color, color.withValues(alpha: 0.7)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
              ),
            ),
          ),
        );
      },
    );
  }
}
