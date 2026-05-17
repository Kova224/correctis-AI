import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/splash_screen.dart';
import 'services/ai_correction_service.dart';
import 'services/auth_service.dart';
import 'services/chatbot_service.dart';
import 'services/exam_service.dart';
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

class CorrectisApp extends StatelessWidget {
  const CorrectisApp({super.key});

  @override
  Widget build(BuildContext context) {
    final aiSvc = AiCorrectionService();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<ExamService>(create: (_) => ExamService(aiSvc)),
        ChangeNotifierProvider<ChatBotService>(create: (_) => ChatBotService()),
        Provider<AiCorrectionService>.value(value: aiSvc),
      ],
      child: MaterialApp(
        title: 'Correctis',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
