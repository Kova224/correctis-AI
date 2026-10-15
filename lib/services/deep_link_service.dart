import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/admin/accept_invitation_screen.dart';

/// Écoute les deep-links `correctis://...` et route en fonction du host.
///
/// Hosts gérés :
///   • `correctis://login-callback?...`  → OAuth Supabase (géré par le SDK)
///   • `correctis://invite?token=XXX`    → push AcceptInvitationScreen
///   • `https://correctis.app/invite?token=XXX` (App Link vérifié) → idem
///
/// À démarrer une seule fois au boot (après `runApp`) en passant la
/// `navigatorKey` de l'`MaterialApp`.
class DeepLinkService {
  final GlobalKey<NavigatorState> navigatorKey;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<AuthState>? _authSub;

  /// Token reçu avant que l'app ne soit prête : on l'applique au prochain
  /// frame disponible.
  String? _pendingInvitationToken;

  DeepLinkService(this.navigatorKey);

  Future<void> initialize() async {
    // 1. Cold start : l'app vient d'être ouverte depuis un lien.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e) {
      debugPrint('[DeepLinkService] getInitialLink erreur : $e');
    }

    // 2. Warm start : l'app était déjà ouverte.
    _linkSub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) =>
          debugPrint('[DeepLinkService] stream erreur : $e'),
    );

    // 3. Si une invitation est en attente, on la déclenche dès que l'user
    //    se connecte (cas : reçoit lien avant connexion).
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.initialSession) {
        WidgetsBinding.instance.addPostFrameCallback((_) => flushPending());
      }
    });
  }

  void dispose() {
    _linkSub?.cancel();
    _authSub?.cancel();
  }

  /// Appelle ceci une fois que l'utilisateur est sur le Home (après login).
  /// Si une invitation a été reçue pendant l'écran d'auth, on la déclenche.
  void flushPending() {
    final token = _pendingInvitationToken;
    if (token == null) return;
    _pendingInvitationToken = null;
    _pushAcceptScreen(token);
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Domaines des App Links vérifiés (https) — cf. AndroidManifest.xml et
  /// infra/app-links/README.md.
  static const Set<String> _appLinkHosts = {'correctis.app', 'www.correctis.app'};

  void _handle(Uri uri) {
    debugPrint('[DeepLinkService] reçu : ${uri.scheme}://${uri.host}${uri.path}');

    // App Link https://correctis.app/invite?token=XXX (audit 15/10/2026)
    final isHttpsInvite = uri.scheme == 'https' &&
        _appLinkHosts.contains(uri.host) &&
        uri.path.startsWith('/invite');

    if (uri.scheme != 'correctis' && !isHttpsInvite) return;

    if (isHttpsInvite || uri.host == 'invite') {
      final token = uri.queryParameters['token'];
      if (token == null || token.isEmpty) return;
      final ctx = navigatorKey.currentState?.context;
      if (ctx == null) {
        // Navigator pas encore prêt : on garde en attente.
        _pendingInvitationToken = token;
      } else {
        _pushAcceptScreen(token);
      }
      return;
    }

    // 'login-callback' est géré directement par le SDK Supabase, rien à faire.
  }

  void _pushAcceptScreen(String token) {
    final navState = navigatorKey.currentState;
    if (navState == null) {
      _pendingInvitationToken = token;
      return;
    }
    navState.push(
      MaterialPageRoute(
        builder: (_) => AcceptInvitationScreen(token: token),
        fullscreenDialog: true,
      ),
    );
  }
}
