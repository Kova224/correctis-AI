import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/credits_service.dart';
import '../services/deep_link_service.dart';
import '../services/establishment_service.dart';
import '../services/exam_service.dart';
import '../services/locale_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/account_deletion_gate.dart';
import 'admin/admin_home_screen.dart';
import 'auth/account_type_picker_screen.dart';
import 'auth/login_screen.dart';
import 'home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.85, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _bootstrap();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthService>();
    final exams = context.read<ExamService>();
    final estab = context.read<EstablishmentService>();
    final locale = context.read<LocaleService>();
    final notif = context.read<NotificationService>();
    final credits = context.read<CreditsService>();
    credits.onLowCredits = notif.notifyQuotaAlmostReached;

    // Important : auth.bootstrap() DOIT terminer en premier car
    // estab.bootstrap() et exams.bootstrap() font des requêtes Supabase
    // qui dépendent de la session restaurée (auth.uid() utilisé par les RLS).
    // Sans ça, race condition : les RLS bloquent les requêtes silencieusement.
    await auth.bootstrap();

    // Le reste peut tourner en parallèle puisqu'ils ne dépendent que d'auth.
    await Future.wait([
      exams.bootstrap(),
      estab.bootstrap(),
      locale.bootstrap(),
      notif.bootstrap(),
      credits.bootstrap(),
    ]);
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final deepLinks = context.read<DeepLinkService>();
    // Michel spec §3 : routing STRICT selon profiles.account_type.
    //   • Pas connecté → LoginScreen
    //   • account_type = 'admin' → AdminHomeScreen (jamais d'écrans de correction)
    //   • account_type = 'teacher' → HomeScreen (jamais d'accès dashboard admin)
    final Widget destination;
    if (!auth.isLoggedIn) {
      destination = const LoginScreen();
    } else if (auth.currentUser?.needsAccountTypePick == true) {
      // Michel : compte fraîchement créé via Google Sign-In → doit
      // choisir Enseignant / Administrateur avant de continuer.
      destination = const AccountTypePickerScreen();
    } else if (auth.currentUser?.isAdminAccount == true) {
      destination = const AccountDeletionGate(child: AdminHomeScreen());
    } else {
      destination = const AccountDeletionGate(child: HomeScreen());
    }
    await Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => destination,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
    // Si un deep-link `correctis://invite?token=XXX` est arrivé pendant le
    // splash, on le déclenche maintenant que le HomeScreen est en place.
    if (auth.isLoggedIn) {
      deepLinks.flushPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo officiel de l'application
                ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Icon(Icons.auto_awesome,
                          size: 64, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                    strokeWidth: 2.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
