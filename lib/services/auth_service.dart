import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_user.dart';

/// Service d'auth en mode démo.
/// Stocke l'utilisateur courant dans SharedPreferences.
/// À remplacer par FirebaseAuth en prod (cf. cahier §3.1).
class AuthService extends ChangeNotifier {
  static const _kCurrentUserKey = 'correctis.currentUser';
  static const _kUsersKey = 'correctis.users';

  AppUser? _currentUser;
  AppUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCurrentUserKey);
    if (raw != null) {
      _currentUser = AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      notifyListeners();
    }
  }

  Future<AppUser> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    if (users.any((u) => u['email'] == email)) {
      throw 'Un compte existe déjà avec cet email.';
    }
    final user = AppUser(
      id: const Uuid().v4(),
      email: email,
      displayName: displayName,
    );
    users.add({
      ...user.toJson(),
      'password': password, // OK en démo, jamais en prod
    });
    await prefs.setString(_kUsersKey, jsonEncode(users));
    await _persistCurrent(prefs, user);
    return user;
  }

  Future<AppUser> login({required String email, required String password}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    final match = users.firstWhere(
      (u) => u['email'] == email && u['password'] == password,
      orElse: () => <String, dynamic>{},
    );
    if (match.isEmpty) {
      // En démo, on accepte aussi un compte de test rapide
      if (email == 'demo@correctis.app' && password == 'demo1234') {
        final demoUser = AppUser(
          id: 'demo-user',
          email: email,
          displayName: 'Prof. Démo',
        );
        await _persistCurrent(prefs, demoUser);
        return demoUser;
      }
      throw 'Identifiants invalides.';
    }
    final user = AppUser.fromJson(match);
    await _persistCurrent(prefs, user);
    return user;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCurrentUserKey);
    _currentUser = null;
    notifyListeners();
  }

  /// Met à jour le profil (nom, email, photo, école, téléphone).
  Future<void> updateProfile({
    String? displayName,
    String? email,
    String? photoPath,
    String? phone,
    String? school,
  }) async {
    if (_currentUser == null) return;
    final updated = _currentUser!.copyWith(
      displayName: displayName,
      email: email,
      photoPath: photoPath,
      phone: phone,
      school: school,
    );
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    final idx = users.indexWhere((u) => u['id'] == updated.id);
    if (idx >= 0) {
      users[idx] = {
        ...users[idx], // garde le password
        ...updated.toJson(),
      };
      await prefs.setString(_kUsersKey, jsonEncode(users));
    }
    await _persistCurrent(prefs, updated);
  }

  /// Vérifie qu'un compte existe avec cet email (utilisé par "Mot de passe oublié").
  Future<bool> emailExists(String email) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    if (email == 'demo@correctis.app') return true;
    return users.any((u) => u['email'] == email);
  }

  /// Réinitialise le mot de passe d'un compte (mode démo : on remplace directement).
  /// En prod : Firebase Auth → sendPasswordResetEmail(email) qui envoie un lien.
  Future<void> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (newPassword.length < 4) throw 'Mot de passe trop court (min. 4 car.).';
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);

    // Cas du compte démo : créer une entrée si elle n'existe pas
    if (email == 'demo@correctis.app') {
      final idx = users.indexWhere((u) => u['email'] == email);
      if (idx >= 0) {
        users[idx] = {...users[idx], 'password': newPassword};
      } else {
        users.add({
          'id': 'demo-user',
          'email': email,
          'displayName': 'Prof. Démo',
          'password': newPassword,
        });
      }
      await prefs.setString(_kUsersKey, jsonEncode(users));
      return;
    }

    final idx = users.indexWhere((u) => u['email'] == email);
    if (idx < 0) throw 'Aucun compte trouvé avec cet email.';
    users[idx] = {...users[idx], 'password': newPassword};
    await prefs.setString(_kUsersKey, jsonEncode(users));
  }

  /// Connexion via Google (mock).
  /// En prod : `google_sign_in` + `firebase_auth` `signInWithCredential`.
  Future<AppUser> signInWithGoogle() => _signInWithProvider(
        provider: 'google',
        defaultEmail: 'professeur@gmail.com',
        defaultName: 'Professeur Google',
      );

  /// Connexion via Facebook (mock).
  /// En prod : `flutter_facebook_auth` + Firebase Auth.
  Future<AppUser> signInWithFacebook() => _signInWithProvider(
        provider: 'facebook',
        defaultEmail: 'professeur@facebook.com',
        defaultName: 'Professeur Facebook',
      );

  /// Connexion via Instagram (mock).
  /// En prod : OAuth Instagram via webview ou plugin tiers.
  Future<AppUser> signInWithInstagram() => _signInWithProvider(
        provider: 'instagram',
        defaultEmail: 'professeur@instagram.com',
        defaultName: 'Professeur Instagram',
      );

  /// Connexion via LinkedIn (mock).
  /// En prod : OAuth LinkedIn (linkedin_login plugin).
  Future<AppUser> signInWithLinkedIn() => _signInWithProvider(
        provider: 'linkedin',
        defaultEmail: 'professeur@linkedin.com',
        defaultName: 'Professeur LinkedIn',
      );

  /// Implémentation commune des connexions sociales (mock).
  Future<AppUser> _signInWithProvider({
    required String provider,
    required String defaultEmail,
    required String defaultName,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);

    var match = users.firstWhere(
      (u) => u['provider'] == provider,
      orElse: () => <String, dynamic>{},
    );

    AppUser user;
    if (match.isEmpty) {
      user = AppUser(
        id: '$provider-${const Uuid().v4()}',
        email: defaultEmail,
        displayName: defaultName,
      );
      users.add({
        ...user.toJson(),
        'provider': provider,
      });
      await prefs.setString(_kUsersKey, jsonEncode(users));
    } else {
      user = AppUser.fromJson(match);
    }

    await _persistCurrent(prefs, user);
    return user;
  }

  /// Change le mot de passe (mode démo).
  /// En prod, déclencher un email de reset via Firebase.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_currentUser == null) throw 'Aucun utilisateur connecté.';
    if (newPassword.length < 4) throw 'Mot de passe trop court (min. 4 car.).';
    final prefs = await SharedPreferences.getInstance();
    final users = _readUsers(prefs);
    final idx = users.indexWhere((u) => u['id'] == _currentUser!.id);
    if (idx < 0) throw 'Utilisateur introuvable.';
    final stored = users[idx]['password'] as String? ?? '';
    // En mode démo, le compte de test n'a pas de password stocké → on accepte demo1234.
    final isDemo = _currentUser!.id == 'demo-user';
    if (!isDemo && stored != currentPassword) {
      throw 'Mot de passe actuel incorrect.';
    }
    if (isDemo && currentPassword != 'demo1234') {
      throw 'Mot de passe actuel incorrect.';
    }
    users[idx] = {
      ...users[idx],
      'password': newPassword,
    };
    await prefs.setString(_kUsersKey, jsonEncode(users));
  }

  // --- helpers ---
  List<Map<String, dynamic>> _readUsers(SharedPreferences prefs) {
    final raw = prefs.getString(_kUsersKey);
    if (raw == null) return <Map<String, dynamic>>[];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> _persistCurrent(SharedPreferences prefs, AppUser user) async {
    _currentUser = user;
    await prefs.setString(_kCurrentUserKey, jsonEncode(user.toJson()));
    notifyListeners();
  }
}
