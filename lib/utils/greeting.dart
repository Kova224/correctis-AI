import 'dart:math';

/// Génère une salutation chaleureuse selon l'heure du jour, avec
/// le titre/nom du professeur et une phrase joviale qui change
/// à chaque appel.
class Greeting {
  final String hello;       // "Bonjour", "Bonsoir", …
  final String emoji;       // 🌅, 👋, 🌙, …
  final String name;        // "M. Mike", "Prof. Démo", …
  final String jovialPhrase;// phrase joviale aléatoire

  const Greeting({
    required this.hello,
    required this.emoji,
    required this.name,
    required this.jovialPhrase,
  });

  String get fullText => '$hello, $name';

  /// Génère une salutation pour le prof connecté.
  static Greeting forUser({
    required String displayName,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    final hour = t.hour;

    final String hello;
    final String emoji;
    if (hour >= 5 && hour < 12) {
      hello = 'Bonjour';
      emoji = '☀️';
    } else if (hour >= 12 && hour < 17) {
      hello = 'Bon après-midi';
      emoji = '🌤️';
    } else if (hour >= 17 && hour < 22) {
      hello = 'Bonsoir';
      emoji = '🌙';
    } else {
      hello = 'Bonne nuit';
      emoji = '🌌';
    }

    return Greeting(
      hello: hello,
      emoji: emoji,
      name: _formatName(displayName),
      jovialPhrase: _pickJovial(t, hour),
    );
  }

  /// Préfixe "M." si le nom a 2+ mots, sinon laisse tel quel.
  /// Conserve les titres existants : "Prof.", "M.", "Mme", "Dr.", "Pr."
  static String _formatName(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return 'Professeur';

    final lower = cleaned.toLowerCase();
    final hasTitle = lower.startsWith('m.') ||
        lower.startsWith('mr ') ||
        lower.startsWith('mr.') ||
        lower.startsWith('mme ') ||
        lower.startsWith('mme.') ||
        lower.startsWith('mlle') ||
        lower.startsWith('dr.') ||
        lower.startsWith('dr ') ||
        lower.startsWith('pr.') ||
        lower.startsWith('pr ') ||
        lower.startsWith('prof.') ||
        lower.startsWith('prof ');
    if (hasTitle) return cleaned;

    final parts = cleaned.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      // Utilise le nom de famille (dernier mot) — usage français : M. Dupont
      return 'M. ${parts.last}';
    }
    return 'M. $cleaned';
  }

  /// Choisit une phrase joviale différente à chaque connexion
  /// (basée sur la minute pour rotation rapide pendant le dev,
  ///  + un peu d'aléatoire).
  static String _pickJovial(DateTime t, int hour) {
    final morning = hour >= 5 && hour < 12;
    final afternoon = hour >= 12 && hour < 17;
    final evening = hour >= 17 && hour < 22;
    final night = hour >= 22 || hour < 5;

    final List<String> pool;
    if (morning) {
      pool = const [
        'Prêt(e) à révolutionner la correction de vos copies ? ✨',
        'Que cette journée vous apporte des élèves brillants 💡',
        'Une bonne tasse de café, et c\'est parti pour les corrections ☕',
        'Vos élèves ont de la chance de vous avoir 🌟',
        'Aujourd\'hui sera une belle journée d\'enseignement 🎓',
        'Faisons gagner du temps à votre matinée 🚀',
        'Bienvenue ! On s\'occupe des notes, vous gardez le sourire 😊',
      ];
    } else if (afternoon) {
      pool = const [
        'On continue à briller cet après-midi ! ✨',
        'Encore quelques copies à corriger ? Allons-y 💪',
        'Profitez de l\'après-midi, on fait le reste 🤖',
        'Bon retour ! Prêt(e) pour la suite ? 📚',
        'Une journée bien remplie mérite un peu d\'aide 🎯',
        'Heureux de vous revoir parmi nous 👋',
      ];
    } else if (evening) {
      pool = const [
        'Une longue journée ? Laissez-nous vous aider 🌙',
        'Le soir, c\'est parfait pour finaliser les notes 📝',
        'Bonne soirée — et bonne correction ! 🌟',
        'Heureux de vous accompagner ce soir 🤝',
        'Encore un effort, et tout sera bouclé ✨',
        'Prenez soin de vous, on s\'occupe du reste 💙',
      ];
    } else if (night) {
      pool = const [
        'Encore au travail à cette heure ? Bravo pour votre dévouement 🌌',
        'On corrige avec vous, même tard dans la nuit 🌙',
        'N\'oubliez pas de vous reposer après ✨',
        'Le calme de la nuit, parfait pour se concentrer 🌃',
        'Vos élèves apprécieront vos efforts demain 💫',
      ];
    } else {
      pool = const [
        'Heureux de vous revoir ! 👋',
        'Prêt(e) à gagner du temps ? 🚀',
      ];
    }

    final seed = t.day * 1000 + t.hour * 60 + t.minute;
    return pool[Random(seed).nextInt(pool.length)];
  }
}
