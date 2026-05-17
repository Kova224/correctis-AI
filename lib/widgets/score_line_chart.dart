import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ScorePoint {
  final String label;       // ex: "Maths 12", date courte
  final double percent;     // 0..100
  const ScorePoint({required this.label, required this.percent});
}

/// Line chart d'évolution des notes moyennes par examen.
/// Courbe lissée + zone colorée sous la courbe + points avec tooltip.
class ScoreLineChart extends StatefulWidget {
  final List<ScorePoint> points;
  final String title;
  final String subtitle;

  const ScoreLineChart({
    super.key,
    required this.points,
    this.title = 'Évolution des moyennes',
    this.subtitle = 'Par examen, dans le temps',
  });

  @override
  State<ScoreLineChart> createState() => _ScoreLineChartState();
}

class _ScoreLineChartState extends State<ScoreLineChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
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
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (pts.isNotEmpty)
                _TrendBadge(points: pts),
            ],
          ),
          const SizedBox(height: 18),
          if (pts.isEmpty)
            Container(
              height: 140,
              alignment: Alignment.center,
              child: Text(
                'Pas encore assez de données',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13,
                ),
              ),
            )
          else
            SizedBox(
              height: 160,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onTapDown: (details) {
                      final idx = _hitTest(
                          details.localPosition.dx, constraints.maxWidth, pts);
                      setState(() => _selectedIndex = idx);
                    },
                    child: AnimatedBuilder(
                      animation: _ctrl,
                      builder: (_, __) => CustomPaint(
                        painter: _LineChartPainter(
                          points: pts,
                          progress: _ctrl.value,
                          selectedIndex: _selectedIndex,
                        ),
                        size: Size(constraints.maxWidth, 160),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (pts.isNotEmpty) ...[
            const SizedBox(height: 6),
            // Labels axe X
            SizedBox(
              height: 26,
              child: Row(
                children: pts.map((p) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        p.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int? _hitTest(double dx, double width, List<ScorePoint> pts) {
    if (pts.isEmpty) return null;
    final step = width / (pts.length - 1).clamp(1, double.infinity);
    final idx = (dx / step).round().clamp(0, pts.length - 1);
    return idx;
  }
}

class _TrendBadge extends StatelessWidget {
  final List<ScorePoint> points;
  const _TrendBadge({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();
    final last = points.last.percent;
    final prev = points[points.length - 2].percent;
    final diff = last - prev;
    final isUp = diff > 0;
    final color = isUp ? AppColors.success : (diff < 0 ? AppColors.danger : AppColors.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isUp
                ? Icons.trending_up_rounded
                : (diff < 0
                    ? Icons.trending_down_rounded
                    : Icons.trending_flat_rounded),
            color: color,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            '${isUp ? "+" : ""}${diff.toStringAsFixed(1)} pt',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<ScorePoint> points;
  final double progress; // 0..1 pour animation
  final int? selectedIndex;

  _LineChartPainter({
    required this.points,
    required this.progress,
    this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Padding interne
    const padTop = 12.0;
    const padBottom = 8.0;
    final chartH = size.height - padTop - padBottom;
    final w = size.width;

    // Grille horizontale légère (0, 25, 50, 75, 100)
    final gridPaint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    for (int i = 0; i <= 4; i++) {
      final y = padTop + chartH * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // Calcule les positions des points (échelle Y = 0..100)
    final positions = <Offset>[];
    final step =
        points.length == 1 ? w / 2 : w / (points.length - 1);
    for (int i = 0; i < points.length; i++) {
      final x = points.length == 1 ? w / 2 : i * step;
      final yRatio = 1 - (points[i].percent / 100).clamp(0.0, 1.0);
      final y = padTop + yRatio * chartH;
      positions.add(Offset(x, y));
    }

    // Animation : limite jusqu'à l'index courant
    final maxIndex = (points.length * progress).clamp(1.0, points.length.toDouble());
    final visibleCount = maxIndex.floor().clamp(1, points.length);
    final partial = maxIndex - visibleCount;

    // Construit le path lissé (cubic) jusqu'au point visible
    final linePath = Path();
    linePath.moveTo(positions[0].dx, positions[0].dy);
    for (int i = 1; i < visibleCount; i++) {
      final p0 = positions[i - 1];
      final p1 = positions[i];
      final cp1 = Offset((p0.dx + p1.dx) / 2, p0.dy);
      final cp2 = Offset((p0.dx + p1.dx) / 2, p1.dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }
    // Point partiel pour fluidité
    if (visibleCount < points.length && partial > 0) {
      final p0 = positions[visibleCount - 1];
      final p1 = positions[visibleCount];
      final interp = Offset(
        p0.dx + (p1.dx - p0.dx) * partial,
        p0.dy + (p1.dy - p0.dy) * partial,
      );
      linePath.lineTo(interp.dx, interp.dy);
    }

    // Zone sous la courbe (gradient)
    final lastX = visibleCount < points.length
        ? positions[visibleCount - 1].dx +
            (positions[visibleCount].dx -
                    positions[visibleCount - 1].dx) *
                partial
        : positions.last.dx;
    final areaPath = Path.from(linePath)
      ..lineTo(lastX, size.height - padBottom)
      ..lineTo(positions[0].dx, size.height - padBottom)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primary.withValues(alpha: 0.25),
          AppColors.primary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, size.height));
    canvas.drawPath(areaPath, areaPaint);

    // Ligne principale
    final linePaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Points
    for (int i = 0; i < visibleCount; i++) {
      final isSel = selectedIndex == i;
      final r = isSel ? 7.0 : 4.0;
      // Anneau extérieur
      canvas.drawCircle(
        positions[i],
        r,
        Paint()..color = AppColors.primary,
      );
      // Anneau intérieur blanc
      canvas.drawCircle(
        positions[i],
        r - 1.5,
        Paint()..color = Colors.white,
      );
      // Point coeur (sélection)
      if (isSel) {
        canvas.drawCircle(
          positions[i],
          r - 3.5,
          Paint()..color = AppColors.primary,
        );
      }
    }

    // Tooltip si point sélectionné
    if (selectedIndex != null && selectedIndex! < visibleCount) {
      final p = positions[selectedIndex!];
      final pct = points[selectedIndex!].percent;
      _drawTooltip(canvas, p, '${pct.toStringAsFixed(0)}%', w);
    }
  }

  void _drawTooltip(Canvas canvas, Offset point, String text, double maxW) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 8.0;
    const padV = 4.0;
    const margin = 4.0;
    final bg = Rect.fromCenter(
      center: Offset(point.dx, point.dy - 20),
      width: tp.width + padH * 2,
      height: tp.height + padV * 2,
    );
    final clipped = Rect.fromLTWH(
      bg.left.clamp(0, maxW - bg.width),
      bg.top - margin,
      bg.width,
      bg.height,
    );
    final rrect =
        RRect.fromRectAndRadius(clipped, const Radius.circular(6));
    canvas.drawRRect(rrect, Paint()..color = AppColors.primary);
    tp.paint(
      canvas,
      Offset(clipped.left + padH, clipped.top + padV),
    );
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.points != points;
  }
}
