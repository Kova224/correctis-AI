import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences utilisateur de notifications (au niveau prof individuel).
/// Persiste localement dans SharedPreferences.
class NotificationPrefs {
  final bool copiesReady;
  final bool invitations;
  final bool quotaWarning;

  const NotificationPrefs({
    this.copiesReady = true,
    this.invitations = true,
    this.quotaWarning = true,
  });

  NotificationPrefs copyWith({
    bool? copiesReady,
    bool? invitations,
    bool? quotaWarning,
  }) =>
      NotificationPrefs(
        copiesReady: copiesReady ?? this.copiesReady,
        invitations: invitations ?? this.invitations,
        quotaWarning: quotaWarning ?? this.quotaWarning,
      );
}

/// Service de notifications locales.
///
/// Gère :
///   • Les préférences utilisateur (3 toggles)
///   • L'affichage de notifications locales (in-app)
///
/// Pour les push (cloud), il faudrait Firebase Cloud Messaging — pas dans
/// le V2. Ici on a uniquement des notifications déclenchées localement
/// (ex: à la fin d'une correction, quand quota presque atteint, etc.).
class NotificationService extends ChangeNotifier {
  static const _keyCopiesReady = 'notif_copies_ready';
  static const _keyInvitations = 'notif_invitations';
  static const _keyQuotaWarning = 'notif_quota_warning';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  NotificationPrefs _prefs = const NotificationPrefs();
  NotificationPrefs get prefs => _prefs;

  bool _initialized = false;

  /// À appeler une fois au démarrage.
  Future<void> bootstrap() async {
    // Charge les prefs depuis SharedPreferences
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = NotificationPrefs(
        copiesReady: p.getBool(_keyCopiesReady) ?? true,
        invitations: p.getBool(_keyInvitations) ?? true,
        quotaWarning: p.getBool(_keyQuotaWarning) ?? true,
      );
    } catch (e) {
      debugPrint('[NotificationService] load prefs erreur : $e');
    }

    // Init du plugin natif
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _plugin.initialize(initSettings);
      _initialized = true;

      // Demande de permission sur Android 13+
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[NotificationService] init plugin erreur : $e');
    }

    notifyListeners();
  }

  Future<void> setCopiesReady(bool v) async {
    _prefs = _prefs.copyWith(copiesReady: v);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyCopiesReady, v);
  }

  Future<void> setInvitations(bool v) async {
    _prefs = _prefs.copyWith(invitations: v);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyInvitations, v);
  }

  Future<void> setQuotaWarning(bool v) async {
    _prefs = _prefs.copyWith(quotaWarning: v);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyQuotaWarning, v);
  }

  /// Affiche une notification locale immédiate.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String channelId = 'correctis_general',
    String channelName = 'Correctis',
  }) async {
    if (!_initialized) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: Importance.high,
        priority: Priority.high,
        color: const Color(0xFF6D28D9), // purple admin
      ),
      iOS: const DarwinNotificationDetails(),
    );
    try {
      await _plugin.show(id, title, body, details);
    } catch (e) {
      debugPrint('[NotificationService] show erreur : $e');
    }
  }

  // ─── Méthodes thématiques (appelées par les services métier) ──────────

  Future<void> notifyCopyGraded(String studentName) async {
    if (!_prefs.copiesReady) return;
    await show(
      id: studentName.hashCode,
      title: 'Copie corrigée',
      body: 'La copie de $studentName est prête.',
    );
  }

  Future<void> notifyQuotaAlmostReached(int remaining) async {
    if (!_prefs.quotaWarning) return;
    await show(
      id: 'quota'.hashCode,
      title: 'Crédits bientôt épuisés',
      body: 'Il vous reste $remaining crédit${remaining > 1 ? "s" : ""}.',
    );
  }

  Future<void> notifyInvitationPending(String email) async {
    if (!_prefs.invitations) return;
    await show(
      id: email.hashCode,
      title: 'Invitation en attente',
      body: '$email n\'a pas encore accepté l\'invitation.',
    );
  }
}
