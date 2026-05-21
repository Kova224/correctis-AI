import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config/supabase_config.dart';
import '../models/app_user.dart';

/// Service d'authentification basé sur Supabase Auth + table `profiles`.
///
/// La séparation `auth.users` ↔ `profiles` est gérée par un trigger SQL :
/// à l'inscription, un profil est créé automatiquement avec les infos de base.
class AuthService extends ChangeNotifier {
  AuthService() {
    // Écoute les changements d'état d'authentification (login/logout/refresh)
    _authSub = _client.auth.onAuthStateChange.listen((event) {
      _syncFromSupabase();
    });
  }

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  StreamSubscription<sb.AuthState>? _authSub;
  AppUser? _currentUser;

  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Bootstrap : restaure la session si l'utilisateur était déjà connecté.
  // ---------------------------------------------------------------------------
  Future<void> bootstrap() async {
    await _syncFromSupabase();
  }

  Future<void> _syncFromSupabase() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      _currentUser = null;
      notifyListeners();
      return;
    }
    final user = session.user;
    try {
      // Récupère le profil étendu
      final row = await _client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      _currentUser = AppUser(
        id: user.id,
        email: row?['email'] as String? ?? user.email ?? '',
        displayName: row?['display_name'] as String? ?? '',
        photoPath: row?['photo_path'] as String?,
        phone: row?['phone'] as String?,
        school: row?['school'] as String?,
      );
    } catch (e) {
      // Pas grave si le profil n'est pas encore créé — on utilise les infos auth basiques
      _currentUser = AppUser(
        id: user.id,
        email: user.email ?? '',
        displayName: user.email?.split('@').first ?? '',
      );
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Inscription
  // ---------------------------------------------------------------------------
  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'displayName': displayName.trim()},
      );
      if (res.user == null) {
        throw 'Inscription échouée. Réessayez.';
      }
      // Le trigger SQL `handle_new_user` crée le profil automatiquement
      // avec le displayName depuis raw_user_meta_data — pas d'upsert nécessaire.

      // Si la confirmation email est désactivée, on est auto-connecté.
      // Si elle est activée, on tente une connexion immédiate (sera bloquée
      // si l'utilisateur doit confirmer son email).
      if (res.session == null) {
        try {
          await _client.auth.signInWithPassword(
            email: email.trim(),
            password: password,
          );
        } on sb.AuthException catch (e) {
          if (e.message.toLowerCase().contains('email not confirmed')) {
            throw 'Compte créé. Vérifiez votre email pour confirmer avant de vous connecter.';
          }
          rethrow;
        }
      }
      await _syncFromSupabase();
      if (_currentUser == null) {
        throw 'Inscription créée — connectez-vous maintenant.';
      }
      return _currentUser!;
    } on sb.AuthException catch (e) {
      throw _translateAuth(e.message);
    } catch (e) {
      throw '$e';
    }
  }

  // ---------------------------------------------------------------------------
  // Connexion email + password
  // ---------------------------------------------------------------------------
  Future<AppUser> login({required String email, required String password}) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (res.user == null) {
        throw 'Identifiants invalides.';
      }
      // Construit un user minimal IMMÉDIATEMENT pour ne pas dépendre du fetch profil
      _currentUser = AppUser(
        id: res.user!.id,
        email: res.user!.email ?? email.trim(),
        displayName: '',
      );
      notifyListeners();
      // Charge le profil complet en arrière-plan (n'échoue jamais)
      try {
        await _syncFromSupabase();
      } catch (_) {
        // ignore : on garde le user minimal
      }
      return _currentUser!;
    } on sb.AuthException catch (e) {
      debugPrint('Login error (AuthException): ${e.message}');
      throw _translateAuth(e.message);
    } catch (e) {
      debugPrint('Login error: $e');
      throw '$e';
    }
  }

  // ---------------------------------------------------------------------------
  // Déconnexion
  // ---------------------------------------------------------------------------
  Future<void> logout() async {
    await _client.auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Mise à jour du profil (nom, email, photo, école, téléphone)
  // ---------------------------------------------------------------------------
  Future<void> updateProfile({
    String? displayName,
    String? email,
    String? photoPath,
    String? phone,
    String? school,
  }) async {
    if (_currentUser == null) return;

    // Upload avatar dans le bucket "avatars" si c'est un fichier local
    String? uploadedPhotoPath = photoPath;
    if (photoPath != null &&
        photoPath.isNotEmpty &&
        !photoPath.startsWith('http')) {
      final file = File(photoPath);
      if (file.existsSync()) {
        try {
          final dotIdx = photoPath.lastIndexOf('.');
          final ext = dotIdx >= 0 ? photoPath.substring(dotIdx) : '.jpg';
          final remotePath = '${_currentUser!.id}/avatar$ext';
          await _client.storage
              .from(SupabaseConfig.avatarsBucket)
              .upload(
                remotePath,
                file,
                fileOptions: const sb.FileOptions(upsert: true),
              );
          uploadedPhotoPath = _client.storage
              .from(SupabaseConfig.avatarsBucket)
              .getPublicUrl(remotePath);
        } catch (e) {
          // Si le bucket n'est pas dispo, garde le chemin local
          uploadedPhotoPath = photoPath;
        }
      }
    } else if (photoPath == '') {
      uploadedPhotoPath = null; // retrait de la photo
    }

    final update = <String, dynamic>{
      if (displayName != null) 'display_name': displayName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (school != null) 'school': school,
      if (uploadedPhotoPath != photoPath || photoPath == '')
        'photo_path': uploadedPhotoPath,
      if (photoPath != null && uploadedPhotoPath != null)
        'photo_path': uploadedPhotoPath,
    };

    if (update.isNotEmpty) {
      await _client
          .from('profiles')
          .update(update)
          .eq('id', _currentUser!.id);
    }

    // Met à jour aussi l'email dans auth.users si fourni
    if (email != null && email != _currentUser!.email) {
      try {
        await _client.auth
            .updateUser(sb.UserAttributes(email: email));
      } catch (_) {
        // L'utilisateur devra peut-être confirmer son email — on ignore l'erreur ici
      }
    }

    await _syncFromSupabase();
  }

  // ---------------------------------------------------------------------------
  // Changement de mot de passe (utilisateur connecté)
  // ---------------------------------------------------------------------------
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_currentUser == null) throw 'Aucun utilisateur connecté.';
    if (newPassword.length < 6) {
      throw 'Mot de passe trop court (min. 6 caractères).';
    }
    // Vérifie le mot de passe actuel en se reconnectant
    try {
      await _client.auth.signInWithPassword(
        email: _currentUser!.email,
        password: currentPassword,
      );
    } on sb.AuthException {
      throw 'Mot de passe actuel incorrect.';
    }
    try {
      await _client.auth.updateUser(
        sb.UserAttributes(password: newPassword),
      );
    } on sb.AuthException catch (e) {
      throw _translateAuth(e.message);
    }
  }

  // ---------------------------------------------------------------------------
  // Mot de passe oublié : envoie un email avec lien de reset (Supabase)
  // ---------------------------------------------------------------------------
  Future<bool> emailExists(String email) async {
    // Supabase ne permet pas de vérifier l'existence d'un email côté client
    // (pour des raisons de sécurité). On retourne toujours true et on laisse
    // resetPasswordForEmail se débrouiller silencieusement si l'email n'existe pas.
    return true;
  }

  Future<void> resetPassword({
    required String email,
    required String newPassword, // ignoré : Supabase envoie un email
  }) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
      // L'utilisateur reçoit un email avec un lien magique pour définir un nouveau mdp.
    } on sb.AuthException catch (e) {
      throw _translateAuth(e.message);
    }
  }

  // ---------------------------------------------------------------------------
  // OAuth — Google / Facebook / LinkedIn (Supabase OAuth)
  // ---------------------------------------------------------------------------
  Future<AppUser> signInWithGoogle() => _signInWithOAuth(sb.OAuthProvider.google);
  Future<AppUser> signInWithFacebook() =>
      _signInWithOAuth(sb.OAuthProvider.facebook);
  Future<AppUser> signInWithLinkedIn() =>
      _signInWithOAuth(sb.OAuthProvider.linkedinOidc);

  /// Instagram n'est pas un provider Supabase natif — pour le démo,
  /// on bascule sur LinkedIn ou on indique "bientôt disponible".
  Future<AppUser> signInWithInstagram() async {
    throw 'Connexion Instagram bientôt disponible. Utilisez Google ou Facebook.';
  }

  Future<AppUser> _signInWithOAuth(sb.OAuthProvider provider) async {
    try {
      await _client.auth.signInWithOAuth(
        provider,
        redirectTo: 'correctis://login-callback',
      );
      // La méthode revient avant la fin du flow OAuth (qui se passe en webview).
      // On attend que onAuthStateChange déclenche le sync.
      await Future.delayed(const Duration(seconds: 1));
      // Si pas encore connecté, on lance un sync silencieux.
      await _syncFromSupabase();
      if (_currentUser == null) {
        throw 'La connexion OAuth a été annulée ou n\'a pas abouti.';
      }
      return _currentUser!;
    } on sb.AuthException catch (e) {
      throw _translateAuth(e.message);
    } catch (e) {
      throw '$e';
    }
  }

  // ---------------------------------------------------------------------------
  // Traduction des erreurs Supabase en messages clairs FR
  // ---------------------------------------------------------------------------
  String _translateAuth(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('invalid login')) return 'Identifiants invalides.';
    if (m.contains('email not confirmed')) {
      return 'Veuillez confirmer votre email avant de vous connecter.';
    }
    if (m.contains('user already registered') || m.contains('already exists')) {
      return 'Un compte existe déjà avec cet email.';
    }
    if (m.contains('password should be at least')) {
      return 'Mot de passe trop court (min. 6 caractères).';
    }
    if (m.contains('rate limit')) {
      return 'Trop de tentatives. Réessayez dans une minute.';
    }
    if (m.contains('weak password')) {
      return 'Mot de passe trop faible. Choisissez une combinaison plus complexe.';
    }
    return msg;
  }
}
