import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Accès aux fichiers des buckets PRIVÉS (copies d'élèves).
///
/// Depuis l'audit du 15/10/2026, le bucket `copies` n'est plus public : un
/// lien vers une copie d'élève ne doit pas rester lisible par n'importe qui
/// indéfiniment. Les URL déjà enregistrées en base gardent le format
/// `.../storage/v1/object/public/copies/<chemin>` ; on en extrait le chemin
/// et on demande un lien signé (valable 1 h) au moment de l'affichage.
class PrivateStorage {
  PrivateStorage._();

  static const String _copiesMarker = '/storage/v1/object/public/copies/';
  static const Duration _signedLifetime = Duration(hours: 1);

  /// Cache url d'origine → (lien signé, date d'expiration locale).
  static final Map<String, (String, DateTime)> _cache = {};

  /// Vrai si l'URL désigne un fichier du bucket privé `copies`.
  static bool isPrivateCopyUrl(String url) => url.contains(_copiesMarker);

  /// Chemin de l'objet dans le bucket `copies` (sans query string).
  static String? copyObjectPath(String url) {
    final i = url.indexOf(_copiesMarker);
    if (i < 0) return null;
    var path = url.substring(i + _copiesMarker.length);
    final q = path.indexOf('?');
    if (q >= 0) path = path.substring(0, q);
    return Uri.decodeComponent(path);
  }

  /// Retourne une URL affichable : lien signé pour une copie privée,
  /// l'URL telle quelle sinon.
  static Future<String> resolve(String url) async {
    if (!isPrivateCopyUrl(url)) return url;
    final cached = _cache[url];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    final path = copyObjectPath(url);
    if (path == null || path.isEmpty) return url;
    try {
      final signed = await Supabase.instance.client.storage
          .from('copies')
          .createSignedUrl(path, _signedLifetime.inSeconds);
      // Marge de 10 min avant l'expiration réelle du lien.
      _cache[url] = (
        signed,
        DateTime.now().add(_signedLifetime - const Duration(minutes: 10)),
      );
      return signed;
    } catch (e) {
      debugPrint('[PrivateStorage.resolve] $e');
      rethrow;
    }
  }

  /// À appeler à la déconnexion : les liens signés sont propres au compte.
  static void clearCache() => _cache.clear();
}
