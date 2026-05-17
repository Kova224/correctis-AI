import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/google_sign_in_button.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/social_logos.dart';
import '../home/home_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: 'demo@correctis.app');
  final _password = TextEditingController(text: 'demo1234');
  bool _loading = false;
  bool _googleLoading = false;
  String? _socialLoading; // 'facebook', 'instagram', 'linkedin'

  // ===== Animations =====
  late final AnimationController _entryCtrl; // entrée des éléments
  late final AnimationController _bgCtrl;    // fond animé continu

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _emailFade;
  late final Animation<Offset> _emailSlide;
  late final Animation<double> _passwordFade;
  late final Animation<Offset> _passwordSlide;
  late final Animation<double> _buttonFade;
  late final Animation<double> _googleFade;
  late final Animation<double> _bottomFade;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    // Logo : 0..0.4 — scale + fade
    _logoScale = Tween<double>(begin: 0.4, end: 1).animate(
      CurvedAnimation(
        parent: _entryCtrl,
        curve: const Interval(0, 0.4, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0, 0.3, curve: Curves.easeIn),
    );

    // Titre : 0.2..0.5
    _titleFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.2, 0.5, curve: Curves.easeIn),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.2, 0.5, curve: Curves.easeOutCubic),
    ));

    // Email : 0.4..0.7
    _emailFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.4, 0.7, curve: Curves.easeIn),
    );
    _emailSlide = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.4, 0.7, curve: Curves.easeOutCubic),
    ));

    // Password : 0.5..0.8
    _passwordFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.5, 0.8, curve: Curves.easeIn),
    );
    _passwordSlide = Tween<Offset>(
      begin: const Offset(-0.3, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.5, 0.8, curve: Curves.easeOutCubic),
    ));

    // Bouton login : 0.7..0.9
    _buttonFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.7, 0.9, curve: Curves.easeIn),
    );

    // Google + séparateur : 0.8..1.0
    _googleFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.8, 1.0, curve: Curves.easeIn),
    );

    // Lien register : 0.9..1.0
    _bottomFade = CurvedAnimation(
      parent: _entryCtrl,
      curve: const Interval(0.9, 1.0, curve: Curves.easeIn),
    );

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _bgCtrl.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await context.read<AuthService>().login(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      await context.read<AuthService>().signInWithGoogle();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _socialSignIn(String provider) async {
    setState(() => _socialLoading = provider);
    try {
      final auth = context.read<AuthService>();
      switch (provider) {
        case 'facebook':
          await auth.signInWithFacebook();
          break;
        case 'instagram':
          await auth.signInWithInstagram();
          break;
        case 'linkedin':
          await auth.signInWithLinkedIn();
          break;
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _socialLoading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // Fond animé : bulles flottantes + dégradé
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgCtrl,
              builder: (_, __) => CustomPaint(
                painter: _AnimatedBackgroundPainter(_bgCtrl.value),
              ),
            ),
          ),
          // Contenu — scroll au-dessus du footer blanc
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 160),
              physics: const ClampingScrollPhysics(),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 30),
                    // === LOGO ===
                    Center(
                      child: FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: _AnimatedLogo(controller: _bgCtrl),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // === TITRE ===
                    FadeTransition(
                      opacity: _titleFade,
                      child: SlideTransition(
                        position: _titleSlide,
                        child: Column(
                          children: [
                            Text(
                              'CORRECTIS',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 5,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Connectez-vous à votre espace enseignant',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    // === EMAIL ===
                    FadeTransition(
                      opacity: _emailFade,
                      child: SlideTransition(
                        position: _emailSlide,
                        child: CustomTextField(
                          hint: 'email@exemple.com',
                          controller: _email,
                          light: true,
                          prefixIcon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Email requis';
                            }
                            if (!v.contains('@')) return 'Email invalide';
                            return null;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // === PASSWORD ===
                    FadeTransition(
                      opacity: _passwordFade,
                      child: SlideTransition(
                        position: _passwordSlide,
                        child: CustomTextField(
                          hint: '••••••••',
                          controller: _password,
                          light: true,
                          prefixIcon: Icons.lock_outline,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _login(),
                          validator: (v) {
                            if (v == null || v.length < 4) {
                              return 'Mot de passe trop court';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                    // === FORGOT PASSWORD ===
                    FadeTransition(
                      opacity: _buttonFade,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            PageRouteBuilder(
                              transitionDuration:
                                  const Duration(milliseconds: 320),
                              pageBuilder: (_, __, ___) =>
                                  const ForgotPasswordScreen(),
                              transitionsBuilder: (_, anim, __, child) {
                                return FadeTransition(
                                  opacity: anim,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0.1, 0),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                        parent: anim,
                                        curve: Curves.easeOutCubic)),
                                    child: child,
                                  ),
                                );
                              },
                            ),
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                          child: const Text(
                            'Mot de passe oublié ?',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // === BOUTON SE CONNECTER ===
                    FadeTransition(
                      opacity: _buttonFade,
                      child: PrimaryButton(
                        label: 'Se connecter',
                        loading: _loading,
                        onPressed: _login,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // === SÉPARATEUR ===
                    FadeTransition(
                      opacity: _googleFade,
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OU',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // === GOOGLE ===
                    FadeTransition(
                      opacity: _googleFade,
                      child: GoogleSignInButton(
                        onPressed: _googleSignIn,
                        loading: _googleLoading,
                      ),
                    ),
                    const SizedBox(height: 22),
                    // === LIEN REGISTER ===
                    FadeTransition(
                      opacity: _bottomFade,
                      child: Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                            PageRouteBuilder(
                              transitionDuration:
                                  const Duration(milliseconds: 320),
                              pageBuilder: (_, __, ___) =>
                                  const RegisterScreen(),
                              transitionsBuilder: (_, anim, __, child) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.1, 0),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                      parent: anim,
                                      curve: Curves.easeOutCubic)),
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                          child: RichText(
                            text: TextSpan(
                              text: 'Nouveau ici ? ',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                              children: const [
                                TextSpan(
                                  text: 'Créer un compte',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
          // === FOOTER BLANC ARRONDI (style CrowdFund) — connexion sociale ===
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FadeTransition(
              opacity: _bottomFade,
              child: _SocialFooter(
                loadingProvider: _socialLoading,
                onFacebookTap: () => _socialSignIn('facebook'),
                onInstagramTap: () => _socialSignIn('instagram'),
                onLinkedInTap: () => _socialSignIn('linkedin'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FOOTER BLANC — style CrowdFund (courbe en haut, 3 logos sociaux officiels)
// =============================================================================
class _SocialFooter extends StatelessWidget {
  final String? loadingProvider;
  final VoidCallback onFacebookTap;
  final VoidCallback onInstagramTap;
  final VoidCallback onLinkedInTap;

  const _SocialFooter({
    this.loadingProvider,
    required this.onFacebookTap,
    required this.onInstagramTap,
    required this.onLinkedInTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(46),
          topRight: Radius.circular(46),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ou connectez-vous avec',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SocialButton(
                    tooltip: 'Continuer avec Facebook',
                    loading: loadingProvider == 'facebook',
                    disabled: loadingProvider != null &&
                        loadingProvider != 'facebook',
                    onTap: onFacebookTap,
                    logo: const FacebookLogo(size: 48),
                  ),
                  const SizedBox(width: 22),
                  _SocialButton(
                    tooltip: 'Continuer avec Instagram',
                    loading: loadingProvider == 'instagram',
                    disabled: loadingProvider != null &&
                        loadingProvider != 'instagram',
                    onTap: onInstagramTap,
                    logo: const InstagramLogo(size: 48),
                  ),
                  const SizedBox(width: 22),
                  _SocialButton(
                    tooltip: 'Continuer avec LinkedIn',
                    loading: loadingProvider == 'linkedin',
                    disabled: loadingProvider != null &&
                        loadingProvider != 'linkedin',
                    onTap: onLinkedInTap,
                    logo: const LinkedInLogo(size: 48),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton wrapper : enveloppe le logo de marque dans un InkWell + indicateur de chargement.
class _SocialButton extends StatelessWidget {
  final Widget logo;
  final String tooltip;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  const _SocialButton({
    required this.logo,
    required this.tooltip,
    required this.onTap,
    this.loading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: GestureDetector(
          onTap: disabled || loading ? null : onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedScale(
                scale: loading ? 0.92 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: logo,
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// LOGO ANIMÉ — léger flottement continu
// =============================================================================
class _AnimatedLogo extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedLogo({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Léger mouvement vertical (flottement)
        final t = controller.value * 2 * math.pi;
        final dy = math.sin(t) * 4;
        // Rotation très subtile
        final rot = math.sin(t * 0.5) * 0.04;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: rot,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.28),
                    Colors.white.withValues(alpha: 0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.30),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.30),
                    blurRadius: 30,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.auto_awesome,
                size: 52,
                color: Colors.white,
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// FOND ANIMÉ — formes flottantes + dégradé
// =============================================================================
class _AnimatedBackgroundPainter extends CustomPainter {
  final double t; // 0..1
  _AnimatedBackgroundPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Dégradé vertical sombre → primary
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.primaryDark,
          AppColors.primary,
          AppColors.primaryLight,
        ],
        stops: [0, 0.55, 1],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bg);

    // Cercles flottants en arrière-plan
    _drawBubble(canvas, size,
        cx: 0.15, cy: 0.20, baseR: 80, phase: 0, opacity: 0.10);
    _drawBubble(canvas, size,
        cx: 0.85, cy: 0.30, baseR: 110, phase: 0.3, opacity: 0.08);
    _drawBubble(canvas, size,
        cx: 0.20, cy: 0.75, baseR: 95, phase: 0.6, opacity: 0.07);
    _drawBubble(canvas, size,
        cx: 0.78, cy: 0.85, baseR: 130, phase: 0.85, opacity: 0.06);
    _drawBubble(canvas, size,
        cx: 0.50, cy: 0.50, baseR: 70, phase: 0.45, opacity: 0.05);

    // Cercle accent (cyan) qui se déplace en oblique
    final accentT = (t + 0.2) % 1.0;
    final ax = size.width * (0.2 + 0.6 * accentT);
    final ay = size.height * (0.85 - 0.6 * accentT);
    canvas.drawCircle(
      Offset(ax, ay),
      90,
      Paint()
        ..color = AppColors.accent.withValues(alpha: 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
    );
  }

  void _drawBubble(
    Canvas canvas,
    Size size, {
    required double cx,
    required double cy,
    required double baseR,
    required double phase,
    required double opacity,
  }) {
    final tt = (t + phase) * 2 * math.pi;
    final dx = math.sin(tt) * 18;
    final dy = math.cos(tt * 0.8) * 12;
    final r = baseR + math.sin(tt * 0.6) * 8;
    final p = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24);
    canvas.drawCircle(
      Offset(size.width * cx + dx, size.height * cy + dy),
      r,
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _AnimatedBackgroundPainter oldDelegate) =>
      oldDelegate.t != t;
}
