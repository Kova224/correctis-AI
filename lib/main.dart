import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'services/ai_correction_service.dart';
import 'services/auth_service.dart';
import 'services/chatbot_service.dart';
import 'services/credits_service.dart';
import 'services/deep_link_service.dart';
import 'services/establishment_service.dart';
import 'services/exam_service.dart';
import 'services/locale_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);

  // Initialisation Supabase (Auth + Postgres + Storage)
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Style barre de status (cohérent avec le header bleu)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // L'orientation est verrouillée en portrait pour le MVP (UI mobile).
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const CorrectisApp());
}

class CorrectisApp extends StatefulWidget {
  const CorrectisApp({super.key});

  @override
  State<CorrectisApp> createState() => _CorrectisAppState();
}

class _CorrectisAppState extends State<CorrectisApp>
    with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navigatorKey =
      GlobalKey<NavigatorState>();
  late final DeepLinkService _deepLinks;
  StreamSubscription<AuthState>? _sessionSub;

  @override
  void initState() {
    super.initState();
    _deepLinks = DeepLinkService(_navigatorKey);
    WidgetsBinding.instance.addObserver(this);
    // Audit 15/10/2026 : les données (examens, crédits, école, devise) n'étaient
    // chargées qu'au splash. Après une connexion depuis l'écran de login, ou un
    // changement de compte sur le même téléphone, l'app affichait des données
    // vides ou celles du compte précédent. On recharge à chaque connexion /
    // déconnexion.
    _sessionSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.signedOut) {
        _reloadSessionData(signedOut: s.event == AuthChangeEvent.signedOut);
      }
    });
    // Démarre l'écoute après le premier frame pour que le navigator existe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deepLinks.initialize();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Au retour en foreground (l'utilisateur revient dans l'app après
    // avoir minimisé), on recharge les copies en cours depuis la DB.
    //
    // La correction tourne côté serveur (Edge Function grade-copy) qui
    // écrit directement le résultat en DB — donc si elle s'est terminée
    // pendant que l'app était en background, le rechargement va
    // récupérer la note finale automatiquement, sans relancer la
    // correction.
    if (state == AppLifecycleState.resumed) {
      final ctx = _navigatorKey.currentContext;
      if (ctx == null) return;
      try {
        final svc = Provider.of<ExamService>(ctx, listen: false);
        svc.refreshProcessingCopies();
      } catch (e) {
        debugPrint('[main] refresh au resume échoué : $e');
      }
      try {
        // Rafraîchit le wallet de crédits — utile après un paiement
        // CinetPay terminé dans le navigateur externe (le webhook a écrit
        // un nouveau lot pendant que l'app était en background).
        final credits = Provider.of<CreditsService>(ctx, listen: false);
        credits.refreshWallet();
        credits.refreshLots();
      } catch (e) {
        debugPrint('[main] refresh credits au resume échoué : $e');
      }
    }
  }

  Future<void> _reloadSessionData({required bool signedOut}) async {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    try {
      final exams = Provider.of<ExamService>(ctx, listen: false);
      final estab = Provider.of<EstablishmentService>(ctx, listen: false);
      final credits = Provider.of<CreditsService>(ctx, listen: false);
      if (signedOut) exams.clearCache();
      await Future.wait([
        if (!signedOut) exams.bootstrap(),
        estab.bootstrap(),
        credits.bootstrap(),
      ]);
    } catch (e) {
      debugPrint('[main] rechargement session échoué : $e');
    }
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _deepLinks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aiSvc = AiCorrectionService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<ExamService>(create: (_) => ExamService(aiSvc)),
        ChangeNotifierProvider<ChatBotService>(create: (_) => ChatBotService()),
        ChangeNotifierProvider<EstablishmentService>(
          create: (_) => EstablishmentService(),
        ),
        ChangeNotifierProvider<LocaleService>(
          create: (_) => LocaleService(),
        ),
        ChangeNotifierProvider<NotificationService>(
          create: (_) => NotificationService(),
        ),
        ChangeNotifierProvider<CreditsService>(
          create: (_) => CreditsService(),
        ),
        Provider<AiCorrectionService>.value(value: aiSvc),
        Provider<DeepLinkService>.value(value: _deepLinks),
      ],
      child: Consumer<LocaleService>(
        builder: (context, localeSvc, _) => MaterialApp(
          title: 'Correctis',
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          locale: localeSvc.locale,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('fr'),
            Locale('en'),
            Locale('ar'),
          ],
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
