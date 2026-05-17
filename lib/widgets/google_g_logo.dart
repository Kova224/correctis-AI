import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo Google officiel "G" multicolore — dessiné avec CustomPainter.
/// Utilise les couleurs officielles : Blue, Red, Yellow, Green.
class GoogleGLogo extends StatelessWidget {
  final double size;
  const GoogleGLogo({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  // Couleurs officielles Google
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.22;
    final radius = (s - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Bleu : côté droit (haut → bar horizontale)
    // start = -22°, sweep ≈ 70°
    canvas.drawArc(
      rect,
      _deg(-22),
      _deg(70),
      false,
      arc(_blue),
    );

    // Bar horizontale bleue (forme du "G")
    final barY = center.dy + stroke * 0.05;
    final barStart = Offset(center.dx + radius * 0.05, barY);
    final barEnd = Offset(center.dx + radius + stroke * 0.5, barY);
    canvas.drawLine(
      barStart,
      barEnd,
      Paint()
        ..color = _blue
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt,
    );
    // Petit arrondi à la jonction (couvre la jointure barre/arc)
    canvas.drawCircle(
      Offset(center.dx + radius, barY),
      stroke / 2,
      Paint()..color = _blue,
    );

    // Vert : bas-droit (de ~48° à ~138°)
    canvas.drawArc(
      rect,
      _deg(48),
      _deg(90),
      false,
      arc(_green),
    );

    // Jaune : bas-gauche & gauche (138° → 218°)
    canvas.drawArc(
      rect,
      _deg(138),
      _deg(80),
      false,
      arc(_yellow),
    );

    // Rouge : haut (218° → 338°)
    canvas.drawArc(
      rect,
      _deg(218),
      _deg(120),
      false,
      arc(_red),
    );

    // Couvre l'extrémité droite de la barre par un petit cercle bleu
    // pour un look propre (rendu Google)
    canvas.drawCircle(
      Offset(barEnd.dx, barY),
      stroke / 2 - 0.5,
      Paint()..color = _blue,
    );
  }

  double _deg(double d) => d * math.pi / 180;

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
