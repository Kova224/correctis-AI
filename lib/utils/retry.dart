import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Helper de retry avec backoff exponentiel.
///
/// Réseau mobile en Afrique = instable. Un upload qui foire en `errno 103`
/// (connection abort) ou `errno 7` (no host) marche souvent au 2ème essai.
/// On retente jusqu'à 3 fois en attendant 1s, 2s, 4s entre les essais.
class RetryHelper {
  /// Exécute [action] avec retry automatique sur les erreurs réseau.
  ///
  /// - [maxAttempts] : nombre TOTAL d'essais (essai initial + retries).
  /// - [initialDelay] : délai avant le 1er retry, doublé à chaque suivant.
  /// - [shouldRetry] : prédicat optionnel pour décider si une exception
  ///   doit déclencher un retry (défaut : retry sur SocketException et
  ///   sur les messages contenant "connection", "host lookup", "timeout").
  static Future<T> run<T>(
    Future<T> Function() action, {
    int maxAttempts = 7, // 1+2+4+8+16+32 = ~63s de patience max avant échec
    Duration initialDelay = const Duration(seconds: 1),
    bool Function(Object e)? shouldRetry,
  }) async {
    final retryPredicate = shouldRetry ?? _defaultShouldRetry;
    Object? lastError;
    StackTrace? lastStack;
    var delay = initialDelay;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        if (attempt > 1) {
          debugPrint('[Retry] tentative $attempt/$maxAttempts...');
        }
        return await action();
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        if (attempt == maxAttempts || !retryPredicate(e)) {
          debugPrint('[Retry] échec définitif après $attempt tentative(s) : $e');
          rethrow;
        }
        debugPrint('[Retry] tentative $attempt échouée ($e) → retry dans ${delay.inMilliseconds}ms');
        await Future.delayed(delay);
        delay *= 2;
      }
    }

    // Théoriquement inaccessible mais nécessaire pour le typage
    if (lastStack != null) {
      Error.throwWithStackTrace(lastError!, lastStack);
    }
    throw lastError!;
  }

  static bool _defaultShouldRetry(Object e) {
    if (e is SocketException) return true;
    final msg = e.toString().toLowerCase();
    return msg.contains('connection') ||
        msg.contains('host lookup') ||
        msg.contains('timeout') ||
        msg.contains('reset') ||
        msg.contains('errno = 7') ||
        msg.contains('errno = 103');
  }
}
