import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/google_sign_in_button.dart';
import '../../widgets/primary_button.dart';
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
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // Contenu — scroll plein écran
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
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
                            if (v == null || v.length < 6) {
                              return 'Mot de passe trop court (min. 6 caractères)';
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
        ],
      ),
    );
  }
}


// =============================================================================
// LOGO ANIMÉ — léger flottement continu, affiche le logo réel de l'app
// =============================================================================
class _AnimatedLogo extends StatelessWidget {
  final AnimationController controller;
  const _AnimatedLogo({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        // Léger flottement vertical
        final t = controller.value * 2 * math.pi;
        final dy = math.sin(t) * 4;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 120,
                  height: 120,
                  color: Colors.white,
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 52,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

