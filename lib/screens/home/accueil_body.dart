import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/credits_service.dart';
import '../../services/exam_service.dart';
import '../../theme/app_theme.dart';

/// Écran d'Accueil — landing page chaleureuse et publicitaire.
///
/// Éléments :
///   - Hero greeting personnalisé (Bonjour + prénom, message selon heure)
///   - Card "Correctis en chiffres" avec counters animés (15s, 95%, 10x)
///   - Carousel auto-scroll "Comment ça marche" (3 étapes)
///   - Ma progression : copies corrigées, examens actifs, crédits
///   - CTA "Commencer" → bascule vers l'onglet Examens
///
/// L'objectif : que le prof se sente accueilli et motivé à corriger.
class AccueilBody extends StatefulWidget {
  final VoidCallback onStart;

  const AccueilBody({super.key, required this.onStart});

  @override
  State<AccueilBody> createState() => _AccueilBodyState();
}

class _AccueilBodyState extends State<AccueilBody>
    with TickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  late final AnimationController _statsCtrl;
  late final PageController _carouselCtrl;
  Timer? _carouselTimer;
  int _carouselPage = 0;

  final _carouselSlides = const [
    _CarouselSlide(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Scannez vos copies',
      description:
          'Prenez une photo claire de chaque copie avec votre téléphone.',
      color: Color(0xFF3B82F6),
    ),
    _CarouselSlide(
      icon: Icons.auto_awesome_rounded,
      title: 'L\'IA corrige en 15 secondes',
      description:
          'Notre IA lit l\'écriture manuscrite et attribue une note motivée.',
      color: Color(0xFF10B981),
    ),
    _CarouselSlide(
      icon: Icons.emoji_events_rounded,
      title: 'Classement + PDFs automatiques',
      description:
          'Recevez le ranking de la classe et les bulletins prêts à imprimer.',
      color: Color(0xFFF59E0B),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _statsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    // Démarre l'animation des stats après 300ms (après le fade-in du header)
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _statsCtrl.forward();
    });

    _carouselCtrl = PageController();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_carouselCtrl.hasClients) return;
      final next = (_carouselPage + 1) % _carouselSlides.length;
      _carouselCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _statsCtrl.dispose();
    _carouselTimer?.cancel();
    _carouselCtrl.dispose();
    super.dispose();
  }

  String _timeOfDayGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Bonne matinée ☀️';
    if (hour < 18) return 'Bel après-midi 🌤️';
    return 'Bonne soirée 🌙';
  }

  String _firstName(String displayName, String email) {
    final source = displayName.trim().isNotEmpty
        ? displayName.trim()
        : email.split('@').first;
    return source.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final examSvc = context.watch<ExamService>();
    final creditsSvc = context.watch<CreditsService>();
    final user = auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    final exams = examSvc.examsForUser(user.id);
    final activeExams = exams.length;
    final correctedCount = exams.fold<int>(
      0,
      (sum, e) =>
          sum +
          examSvc
              .copiesFor(e.id)
              .where((c) => c.gradedAt != null)
              .length,
    );
    final creditsBalance = creditsSvc.availableCredits;
    final firstName = _firstName(user.displayName, user.email);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
        children: [
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // HERO GREETING
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.0,
            child: Text(
              'BIENVENUE',
              style: AppFonts.mono(
                fontSize: 11,
                color: AppColors.textMuted,
                letterSpacing: 2.4,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.05,
            child: Text(
              firstName,
              style: AppFonts.fraunces(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 6),
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.10,
            child: Text(
              _timeOfDayGreeting(),
              style: AppFonts.sans(
                fontSize: 14.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),

          const SizedBox(height: 26),

          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // CORRECTIS EN CHIFFRES (counters animés)
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.15,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F2A4A), Color(0xFF0A1929)],
                ),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: AppColors.profPrimary.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'CORRECTIS EN CHIFFRES',
                    style: AppFonts.mono(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _AnimatedStatBox(
                        controller: _statsCtrl,
                        end: 15,
                        suffix: 's',
                        label: 'par copie',
                        icon: Icons.bolt_rounded,
                        color: const Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 8),
                      _AnimatedStatBox(
                        controller: _statsCtrl,
                        end: 95,
                        suffix: '%',
                        label: 'précision',
                        icon: Icons.center_focus_strong_rounded,
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 8),
                      _AnimatedStatBox(
                        controller: _statsCtrl,
                        end: 10,
                        suffix: 'x',
                        label: 'plus vite',
                        icon: Icons.rocket_launch_rounded,
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // COMMENT ÇA MARCHE (carousel auto-scroll)
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.22,
            child: Text(
              'COMMENT ÇA MARCHE',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.25,
            child: SizedBox(
              height: 155,
              child: PageView.builder(
                controller: _carouselCtrl,
                itemCount: _carouselSlides.length,
                onPageChanged: (i) => setState(() => _carouselPage = i),
                itemBuilder: (context, i) => _CarouselCard(
                  slide: _carouselSlides[i],
                  index: i + 1,
                  total: _carouselSlides.length,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _carouselSlides.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _carouselPage ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _carouselPage
                      ? AppColors.profPrimary
                      : AppColors.borderSubtle,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),

          const SizedBox(height: 26),

          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // VOTRE PROGRESSION
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.30,
            child: Text(
              'VOTRE PROGRESSION',
              style: AppFonts.mono(
                fontSize: 10,
                color: AppColors.textMuted,
                letterSpacing: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.33,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border.all(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Column(
                children: [
                  _ProgressRow(
                    icon: Icons.assignment_turned_in_rounded,
                    label: 'Copies corrigées',
                    value: '$correctedCount',
                    color: const Color(0xFF10B981),
                  ),
                  const Divider(
                    height: 22,
                    color: AppColors.borderSubtle,
                    thickness: 0.6,
                  ),
                  _ProgressRow(
                    icon: Icons.folder_open_rounded,
                    label: 'Examens actifs',
                    value: '$activeExams',
                    color: const Color(0xFF3B82F6),
                  ),
                  const Divider(
                    height: 22,
                    color: AppColors.borderSubtle,
                    thickness: 0.6,
                  ),
                  _ProgressRow(
                    icon: Icons.savings_rounded,
                    label: 'Crédits disponibles',
                    value: '$creditsBalance',
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),

          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // CTA COMMENCER
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.40,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: AppColors.profGradient,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.profPrimary.withValues(alpha: 0.42),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  onTap: widget.onStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.rocket_launch_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'COMMENCER',
                          style: AppFonts.mono(
                            fontSize: 12,
                            color: Colors.white,
                            letterSpacing: 1.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _FadeSlideIn(
            controller: _fadeCtrl,
            delay: 0.45,
            child: Text(
              'Accédez à vos examens et lancez la correction',
              style: AppFonts.sans(
                fontSize: 11,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

}

// ══════════════════════════════════════════════════════════════════════════
// Widgets internes
// ══════════════════════════════════════════════════════════════════════════

/// Fade + slide up depuis 20px avec délai configurable (en fraction du controller).
class _FadeSlideIn extends StatelessWidget {
  final AnimationController controller;
  final double delay; // 0.0 - 1.0
  final Widget child;

  const _FadeSlideIn({
    required this.controller,
    required this.delay,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * 20),
            child: child,
          ),
        );
      },
    );
  }
}

/// Compteur animé (0 → end) dans une box avec icône et couleur.
class _AnimatedStatBox extends StatelessWidget {
  final AnimationController controller;
  final int end;
  final String suffix;
  final String label;
  final IconData icon;
  final Color color;

  const _AnimatedStatBox({
    required this.controller,
    required this.end,
    required this.suffix,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final val = (controller.value * end).round();
                return Text(
                  '$val$suffix',
                  style: AppFonts.fraunces(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                );
              },
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppFonts.sans(
                fontSize: 10,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselSlide {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _CarouselSlide({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

class _CarouselCard extends StatelessWidget {
  final _CarouselSlide slide;
  final int index;
  final int total;

  const _CarouselCard({
    required this.slide,
    required this.index,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: slide.color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: slide.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Icon(slide.icon, color: slide.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ÉTAPE $index / $total',
                  style: AppFonts.mono(
                    fontSize: 9,
                    color: slide.color,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  slide.title,
                  style: AppFonts.fraunces(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  slide.description,
                  style: AppFonts.sans(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ProgressRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: AppFonts.sans(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: AppFonts.fraunces(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
