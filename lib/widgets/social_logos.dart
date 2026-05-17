import 'package:flutter/material.dart';

/// Logos sociaux officiels avec leurs couleurs de marque exactes.
/// Utilisés comme boutons de connexion sociale.

// =============================================================================
// FACEBOOK — "f" blanc sur cercle bleu #1877F2
// =============================================================================
class FacebookLogo extends StatelessWidget {
  final double size;
  const FacebookLogo({super.key, this.size = 44});

  static const Color brandColor = Color(0xFF1877F2);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: brandColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.only(bottom: size * 0.04),
          child: Text(
            'f',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.62,
              fontWeight: FontWeight.w900,
              fontFamily: 'Helvetica',
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// INSTAGRAM — Carré arrondi avec gradient officiel + icône caméra
// =============================================================================
class InstagramLogo extends StatelessWidget {
  final double size;
  const InstagramLogo({super.key, this.size = 44});

  // Gradient officiel Instagram (de bas-gauche à haut-droite)
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [
      Color(0xFFFEDA77), // jaune
      Color(0xFFF58529), // orange
      Color(0xFFDD2A7B), // rose magenta
      Color(0xFF8134AF), // violet
      Color(0xFF515BD4), // bleu-violet
    ],
    stops: [0, 0.25, 0.5, 0.75, 1],
  );

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.28;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: CustomPaint(painter: _InstagramIconPainter(size)),
    );
  }
}

class _InstagramIconPainter extends CustomPainter {
  final double containerSize;
  _InstagramIconPainter(this.containerSize);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final strokeW = size.width * 0.075;

    // Carré arrondi extérieur (cadre)
    final outerRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: size.width * 0.58,
      height: size.height * 0.58,
    );
    final outerStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW;
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      Radius.circular(size.width * 0.13),
    );
    canvas.drawRRect(outerRRect, outerStroke);

    // Cercle objectif au centre
    canvas.drawCircle(
      Offset(cx, cy),
      size.width * 0.155,
      outerStroke,
    );

    // Petit point (flash) en haut à droite
    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(
      Offset(cx + size.width * 0.20, cy - size.height * 0.20),
      size.width * 0.045,
      dot,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// LINKEDIN — "in" blanc sur carré arrondi bleu #0A66C2
// =============================================================================
class LinkedInLogo extends StatelessWidget {
  final double size;
  const LinkedInLogo({super.key, this.size = 44});

  static const Color brandColor = Color(0xFF0A66C2);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: brandColor,
        borderRadius: BorderRadius.circular(size * 0.20),
      ),
      child: CustomPaint(painter: _LinkedInIconPainter(size)),
    );
  }
}

class _LinkedInIconPainter extends CustomPainter {
  final double containerSize;
  _LinkedInIconPainter(this.containerSize);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final p = Paint()..color = Colors.white;

    // Le "i" : petit carré (point) + barre verticale
    final iX = w * 0.28;
    final dotSize = w * 0.13;
    // Point au-dessus du i
    final dotRect = Rect.fromCenter(
      center: Offset(iX, h * 0.32),
      width: dotSize,
      height: dotSize,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(dotRect, Radius.circular(dotSize * 0.15)),
      p,
    );
    // Barre verticale du i
    final iBar = Rect.fromCenter(
      center: Offset(iX, h * 0.62),
      width: dotSize,
      height: h * 0.32,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(iBar, Radius.circular(dotSize * 0.15)),
      p,
    );

    // Le "n" : barre verticale + courbe + barre verticale (forme "n")
    final nLeftX = w * 0.48;
    final nRightX = w * 0.72;
    final nBarW = dotSize;
    final nTop = h * 0.45;
    final nBottom = h * 0.78;

    // Barre gauche du n
    final nLeft = Rect.fromLTRB(
      nLeftX - nBarW / 2,
      nTop,
      nLeftX + nBarW / 2,
      nBottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(nLeft, Radius.circular(nBarW * 0.15)),
      p,
    );

    // Barre droite du n
    final nRight = Rect.fromLTRB(
      nRightX - nBarW / 2,
      nTop,
      nRightX + nBarW / 2,
      nBottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(nRight, Radius.circular(nBarW * 0.15)),
      p,
    );

    // Petite barre horizontale au sommet du n (arrondi)
    final nTopBar = Rect.fromLTRB(
      nLeftX - nBarW / 2,
      nTop,
      nRightX + nBarW / 2,
      nTop + nBarW * 0.9,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(nTopBar, Radius.circular(nBarW * 0.45)),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
