import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Langues supportées par l'app.
enum AppLanguage {
  french('fr', 'Français', '🇫🇷'),
  english('en', 'English', '🇬🇧'),
  arabic('ar', 'العربية', '🇸🇦');

  final String code;
  final String label;
  final String flag;
  const AppLanguage(this.code, this.label, this.flag);

  static AppLanguage fromCode(String? code) =>
      AppLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => AppLanguage.french,
      );

  Locale toLocale() => Locale(code);
}

/// Service de gestion de la langue de l'app.
///
/// Persiste le choix dans SharedPreferences et notifie les listeners pour
/// que MaterialApp se reconstruise avec la nouvelle Locale.
class LocaleService extends ChangeNotifier {
  static const _prefsKey = 'app_language';

  AppLanguage _current = AppLanguage.french;
  AppLanguage get current => _current;
  Locale get locale => _current.toLocale();

  /// Charge la langue sauvegardée au démarrage.
  Future<void> bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_prefsKey);
      _current = AppLanguage.fromCode(code);
      notifyListeners();
    } catch (e) {
      debugPrint('[LocaleService] bootstrap erreur : $e');
    }
  }

  /// Change la langue active et persiste le choix.
  Future<void> setLanguage(AppLanguage lang) async {
    if (_current == lang) return;
    _current = lang;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, lang.code);
    } catch (e) {
      debugPrint('[LocaleService] setLanguage erreur : $e');
    }
  }
}
