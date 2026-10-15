import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_deletion_gate.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/google_sign_in_button.dart';
import '../admin/admin_home_screen.dart';
import '../admin/paste_invitation_token_screen.dart';
import '../home/home_screen.dart';
import 'account_type_picker_screen.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Email pré-rempli (utilisé quand on arrive depuis un lien d'invitation
  /// enseignant — le champ email est rempli automatiquement avec celui
  /// de l'invitation).
  final String? prefilledEmail;

  const LoginScreen({super.key, this.prefilledEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
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

    _email = TextEditingController(text: widget.prefilledEmail ?? '');

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
      final user = await context.read<AuthService>().login(
            email: _email.text.trim(),
            password: _password.text,
          );
      if (!mounted) return;
      // Michel spec §3 : admin → AdminHomeScreen, prof → HomeScreen
      // Suppression de compte en cours → proposer de l'annuler.
      final Widget destination = AccountDeletionGate(
        child: user.isAdminAccount
            ? const AdminHomeScreen()
            : const HomeScreen(),
      );
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, __, ___) => destination,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (r) => false,
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
      final user = await context.read<AuthService>().signInWithGoogle();
      if (!mounted) return;
      // Michel : compte Google fraîchement créé → picker Enseignant/Admin.
      // Sinon route directement selon account_type existant.
      final Widget destination = user.needsAccountTypePick
          ? const AccountTypePickerScreen()
          : AccountDeletionGate(
              child: user.isAdminAccount
                  ? const AdminHomeScreen()
                  : const HomeScreen(),
            );
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, __, ___) => destination,
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (r) => false,
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
      backgroundColor: AppColors.voidBg,
      body: Container(
        // Fond void avec dégradé radial subtil (style hero maquette)
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.8),
            radius: 1.5,
            colors: [
              Color(0xFF0A1F3E),
              AppColors.voidBg,
            ],
            stops: [0.0, 0.7],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
            physics: const ClampingScrollPhysics(),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  // === LOGO CORRECTIS — gradient "shiny" maquette ===
                  Center(
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: ShaderMask(
                          shaderCallback: (bounds) =>
                              AppColors.logoGradient.createShader(bounds),
                          child: Text(
                            'CORRECTIS',
                            textAlign: TextAlign.center,
                            style: AppFonts.fraunces(
                              fontSize: 52,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ).copyWith(letterSpacing: -1),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // === SLOGAN ===
                  FadeTransition(
                    opacity: _titleFade,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: Column(
                        children: [
                          Text(
                            'CORRECTION INTELLIGENTE · CONFIANCE TOTALE',
                            textAlign: TextAlign.center,
                            style: AppFonts.mono(
                              fontSize: 10,
                              color: AppColors.textMuted,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Connectez-vous à votre\nespace enseignant',
                            textAlign: TextAlign.center,
                            style: AppFonts.fraunces(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ).copyWith(height: 1.3),
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
                  // === MOT DE PASSE OUBLIÉ ===
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
                        child: Text(
                          'Mot de passe oublié ?',
                          style: AppFonts.sans(
                            fontSize: 12,
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // === BOUTON SE CONNECTER (gradient vert prof) ===
                  FadeTransition(
                    opacity: _buttonFade,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: AppColors.profGradient,
                        borderRadius:
                            BorderRadius.circular(AppRadius.pill),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.profPrimary
                                .withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                          onTap: _loading ? null : _login,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      'SE CONNECTER',
                                      style: AppFonts.mono(
                                        fontSize: 12,
                                        color: Colors.white,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  // === SÉPARATEUR ===
                  FadeTransition(
                    opacity: _googleFade,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Divider(
                            color: AppColors.borderSubtle,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14),
                          child: Text(
                            'OU',
                            style: AppFonts.mono(
                              fontSize: 11,
                              color: AppColors.textMuted,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(
                            color: AppColors.borderSubtle,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // === GOOGLE ===
                  FadeTransition(
                    opacity: _googleFade,
                    child: GoogleSignInButton(
                      onPressed: _googleSignIn,
                      loading: _googleLoading,
                    ),
                  ),
                  const SizedBox(height: 28),
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
                            style: AppFonts.sans(
                              fontSize: 13,
                              color: AppColors.textMuted,
                            ),
                            children: [
                              TextSpan(
                                text: 'Créer un compte',
                                style: AppFonts.sans(
                                  fontSize: 13,
                                  color: AppColors.profPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Retour Michel : bloc "J'ai un code d'invitation" retiré.
                  // Le prof rejoint une école via "Mes écoles" dans son profil
                  // une fois connecté (nouveau flow email + identifiant).
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// _AnimatedLogo supprimé — remplacé par ShaderMask logo gradient dans le build.

