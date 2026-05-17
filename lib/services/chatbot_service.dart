import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';

/// Service du chatbot Correctis — mode démo avec base de connaissances locale.
/// En prod, remplacer `_generateResponse()` par un appel à un vrai LLM
/// (Claude / GPT) avec un system prompt spécialisé.
class ChatBotService extends ChangeNotifier {
  static const _kHistoryKey = 'correctis.chat.history';
  static const _uuid = Uuid();

  final List<ChatMessage> _messages = <ChatMessage>[];
  bool _bootstrapped = false;
  bool _typing = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isTyping => _typing;
  bool get isEmpty => _messages.isEmpty;

  /// Charge l'historique depuis le disque + envoie le message d'accueil si vide.
  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistoryKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _messages
        ..clear()
        ..addAll(
            list.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)));
    }
    if (_messages.isEmpty) {
      _addBot(_welcomeText, suggestions: _initialSuggestions);
    }
    notifyListeners();
  }

  /// Réinitialise la conversation (utile pour un bouton "Nouvelle discussion").
  Future<void> reset() async {
    _messages.clear();
    _addBot(_welcomeText, suggestions: _initialSuggestions);
    await _persist();
    notifyListeners();
  }

  /// Envoi d'un message utilisateur + réponse du bot.
  Future<void> sendUserMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _messages.add(ChatMessage(
      id: _uuid.v4(),
      role: ChatRole.user,
      text: clean,
    ));
    notifyListeners();
    _typing = true;
    notifyListeners();

    // Délai simulé "le bot écrit…"
    await Future.delayed(Duration(milliseconds: 700 + Random().nextInt(900)));

    final response = _generateResponse(clean);
    _typing = false;
    _addBot(response.text, suggestions: response.suggestions);
    await _persist();
    notifyListeners();
  }

  void _addBot(String text, {List<String>? suggestions}) {
    _messages.add(ChatMessage(
      id: _uuid.v4(),
      role: ChatRole.bot,
      text: text,
      suggestions: suggestions,
    ));
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kHistoryKey,
      jsonEncode(_messages.map((m) => m.toJson()).toList()),
    );
  }

  // ---------------------------------------------------------------------------
  // BASE DE CONNAISSANCES
  // ---------------------------------------------------------------------------

  static const _welcomeText =
      'Bonjour 👋 Je suis **Correctis Chatbot**, votre assistant. '
      'Je peux vous guider pas à pas dans l\'utilisation de l\'application '
      'ou simplement discuter avec vous.\n\n'
      'Que souhaitez-vous faire ?';

  static const _initialSuggestions = <String>[
    'Comment créer un examen ?',
    'Comment scanner les copies ?',
    'Comment fonctionne le classement ?',
    'Exporter en Excel',
    'Je débute, par où commencer ?',
  ];

  _BotResponse _generateResponse(String userText) {
    final t = _normalize(userText);

    // Salutations
    if (_match(t, ['bonjour', 'salut', 'hello', 'coucou', 'hey', 'hi'])) {
      return _BotResponse(
        'Bonjour ! Ravi de vous parler. Voulez-vous que je vous explique une fonctionnalité de Correctis ?',
        suggestions: const [
          'Créer mon premier examen',
          'À quoi sert la source de correction ?',
          'Voir les statistiques',
        ],
      );
    }
    if (_match(t, ['merci', 'thanks', 'thank you', 'cool', 'super', 'parfait'])) {
      return const _BotResponse(
        'Avec plaisir 😊 N\'hésitez pas à me solliciter à tout moment.',
        suggestions: [
          'Voir d\'autres fonctionnalités',
          'Comment exporter les résultats ?',
        ],
      );
    }
    if (_match(t, ['au revoir', 'bye', 'a plus', 'a+', 'ciao'])) {
      return const _BotResponse(
        'À bientôt ! Bonne correction 👨‍🏫',
      );
    }

    // Création d'examen
    if (_match(t, ['creer', 'cree', 'nouveau', 'ajouter']) &&
        _match(t, ['examen', 'evaluation', 'devoir', 'controle', 'exam'])) {
      return const _BotResponse(
        '📘 **Créer un examen :**\n'
        '1. Sur l\'écran d\'accueil, appuyez sur le bouton **+ Nouvel examen** en bas\n'
        '2. Remplissez le titre, la classe, la note totale\n'
        '3. Choisissez la **langue** et le **type d\'examen** (math, sciences, lettres…)\n'
        '4. Importez le sujet (caméra ou galerie)\n'
        '5. L\'IA extrait les questions et le barème — vous pouvez les modifier\n'
        '6. Validez le sujet et choisissez la **source de correction**',
        suggestions: [
          'Comment importer un sujet ?',
          'Saisie manuelle du sujet',
          'Source de correction ?',
        ],
      );
    }

    // Saisie manuelle
    if (_match(t, ['saisie manuelle', 'manuel', 'taper', 'recopier']) ||
        _match(t, ['exact', 'fidele']) ||
        _match(t, ['copier', 'coller'])) {
      return const _BotResponse(
        '✍️ **Saisie manuelle du sujet :**\n'
        'Dans l\'écran de validation du sujet, appuyez sur **« Saisie manuelle »**.\n\n'
        'Format : une ligne titre puis le contenu.\n'
        '```\n'
        'Exercice 1 (5 pts)\n'
        'Énoncé complet ici…\n'
        'a) Sous-question  /1.5\n'
        'b) Sous-question  /2\n'
        '\n'
        'Exercice 2 (4 pts)\n'
        '...\n'
        '```\n'
        'Les symboles, formules et équations sont conservés tels quels.',
        suggestions: [
          'Comment ajouter des sous-questions ?',
          'Modifier le barème',
        ],
      );
    }

    // Sous-questions
    if (_match(t, ['sous question', 'sous-question', 'subquestion', 'a b c'])) {
      return const _BotResponse(
        '🔢 **Sous-questions (a, b, c…) :**\n'
        'Dans l\'éditeur de validation du sujet :\n'
        '• Tapez sur une question existante → bouton **« Ajouter une sous-question »**\n'
        '• Chaque sous-question a son propre énoncé et sa note (ex : a) /1.5)\n'
        '• La note totale de l\'exercice = somme des sous-questions\n'
        '• Vous pouvez glisser-déposer pour réordonner',
      );
    }

    // Source de correction
    if (_match(t, ['source', 'correction']) ||
        _match(t, ['corrige type', 'corrigé type'])) {
      return const _BotResponse(
        '🎯 **Source de correction :**\n'
        'Trois options possibles :\n\n'
        '**A · Corrigé type** — importez un ou plusieurs documents (photos/PDF) qui serviront de référence.\n'
        '**B · Cours / Support** — l\'IA évalue par rapport à votre cours.\n'
        '**C · Génération IA** — l\'IA propose un corrigé à partir du sujet, que vous validez.\n\n'
        'Pour l\'option C, **la validation du corrigé est obligatoire** avant correction.',
        suggestions: [
          'Comment scanner les copies ?',
          'Modifier le corrigé IA',
        ],
      );
    }

    // Scanner copies
    if (_match(t, ['scan', 'scanner', 'photographier', 'capture']) &&
        _match(t, ['copie', 'eleve', 'élève'])) {
      return const _BotResponse(
        '📷 **Scanner une copie :**\n'
        '1. Ouvrez l\'examen → bouton **« Scanner une copie »** en bas\n'
        '2. Saisissez le **nom et le PV/matricule** de l\'élève\n'
        '3. Photographiez chaque page une à une (ou choisissez depuis la galerie)\n'
        '4. Réorganisez ou supprimez les pages si besoin\n'
        '5. Cliquez sur **« Terminer cette copie »** ou **« Nouvel élève »**\n\n'
        '⚠️ Une alerte apparaît si vous tentez de quitter sans valider — c\'est volontaire pour éviter les pertes.',
        suggestions: [
          'Modifier les notes après IA',
          'Voir le classement',
        ],
      );
    }

    // Multi-pages
    if (_match(t, ['plusieurs pages', 'multi page', 'recto verso'])) {
      return const _BotResponse(
        '📄 **Multi-pages :**\n'
        'Lors du scan, chaque tap sur **« Scanner »** ajoute une page.\n'
        'Vous voyez la galerie des pages avec leur ordre (1/3, 2/3…).\n'
        'Faites glisser pour réordonner, swipe pour supprimer.\n'
        'Toutes les pages sont liées au même élève — pas de mélange possible entre élèves.',
      );
    }

    // Classement / ranking
    if (_match(t, ['classement', 'ranking', 'rang', 'podium', 'top'])) {
      return const _BotResponse(
        '🏆 **Classement automatique :**\n'
        'Une fois quelques copies corrigées :\n'
        '1. Ouvrez l\'examen\n'
        '2. Appuyez sur **« Générer le classement »** (carte bleue dorée)\n'
        '3. Le **podium top 3** apparaît avec médailles or/argent/bronze\n'
        '4. La liste complète suit avec mention (Excellent, Très bien, Bien, Passable, Insuffisant)\n'
        '5. Bouton **« Exporter en Excel »** pour partager le classement\n\n'
        'Le classement par classe est visible aussi sur l\'accueil dans le graphique des meilleurs élèves.',
        suggestions: [
          'Filtrer par classe',
          'Exporter en Excel',
        ],
      );
    }

    // Export Excel
    if (_match(t, ['excel', 'export', 'xlsx', 'tableau', 'fichier'])) {
      return const _BotResponse(
        '📊 **Export Excel :**\n'
        '• **Notes par question :** dans l\'examen → bouton **« Excel »** en haut de la liste des copies. Génère un fichier avec une colonne par sous-question.\n'
        '• **Classement :** écran de classement → **« Exporter en Excel »**. Génère un fichier avec rang, nom, note, % et mention.\n\n'
        'Les fichiers s\'ouvrent avec le partage natif Android/iOS — vous pouvez les envoyer par email, WhatsApp, etc.',
      );
    }

    // Profil / compte
    if (_match(t, ['profil', 'compte', 'mot de passe', 'password', 'photo', 'avatar'])) {
      return const _BotResponse(
        '👤 **Mon profil :**\n'
        'Tapez sur votre **avatar** en haut à droite de l\'accueil ou sur l\'onglet **« Profil »** en bas.\n\n'
        'Vous pouvez :\n'
        '• Changer votre **photo de profil** (caméra ou galerie)\n'
        '• Modifier nom, email, téléphone, école\n'
        '• Changer votre **mot de passe**\n'
        '• Voir vos statistiques (examens créés, copies corrigées, moyenne)\n'
        '• Vous **déconnecter**',
      );
    }

    // Modifier les notes
    if (_match(t, ['modifier', 'changer', 'corriger']) &&
        _match(t, ['note', 'score', 'point'])) {
      return const _BotResponse(
        '✏️ **Modifier une note :**\n'
        '1. Ouvrez la copie d\'un élève (depuis la liste de l\'examen)\n'
        '2. Appuyez sur l\'icône **crayon** en haut à droite\n'
        '3. Modifiez la note ou le commentaire de chaque sous-question\n'
        '4. Quittez le mode édition (icône check) — c\'est sauvegardé automatiquement',
      );
    }

    // Statistiques / dashboard
    if (_match(t, ['statistique', 'graphique', 'dashboard', 'meilleur', 'top eleve'])) {
      return const _BotResponse(
        '📈 **Dashboard / Meilleurs élèves :**\n'
        'Sur l\'écran d\'accueil, la carte **« Meilleurs élèves »** affiche le top 5 des élèves.\n'
        '• Par défaut : toutes classes confondues\n'
        '• Cliquez sur une classe (chips horizontales) pour filtrer\n'
        '• Le 1er apparaît en cyan, les autres en bleu\n'
        '• Les barres s\'animent à chaque mise à jour',
      );
    }

    // Langues
    if (_match(t, ['langue', 'langues', 'multilingue', 'francais', 'anglais', 'arabe'])) {
      return const _BotResponse(
        '🌍 **Langues supportées :**\n'
        'Français, Anglais, Arabe, Espagnol, Allemand, Italien, Portugais.\n'
        'Choisissez la langue de l\'examen lors de sa création — elle aide l\'IA à mieux extraire les questions et à corriger.',
      );
    }

    // Confiance IA
    if (_match(t, ['confiance', 'fiabilite', 'erreur ia', 'ia se trompe'])) {
      return const _BotResponse(
        '🎯 **Confiance de l\'IA :**\n'
        'Chaque copie corrigée affiche un **indicateur de confiance** (en %). Plus c\'est élevé, plus l\'IA est sûre de sa correction.\n\n'
        'Pour les copies à faible confiance, vérifiez manuellement et ajustez les notes — l\'IA n\'est jamais à 100% fiable, surtout sur les écritures peu lisibles.',
      );
    }

    // Débuter
    if (_match(t, ['debut', 'commencer', 'comment ca marche', 'tutoriel', 'guide']) ||
        _match(t, ['premiere fois', 'nouveau ici'])) {
      return const _BotResponse(
        '🚀 **Pour commencer :**\n\n'
        '**1.** Créez votre premier examen avec le bouton **+ Nouvel examen**\n'
        '**2.** Importez le sujet (photo/galerie) — l\'IA extrait les questions\n'
        '**3.** Vérifiez le barème et validez\n'
        '**4.** Choisissez votre source de correction\n'
        '**5.** Scannez les copies de vos élèves\n'
        '**6.** Patientez quelques secondes pour la correction IA\n'
        '**7.** Consultez les notes, ajustez si besoin\n'
        '**8.** Générez le classement et exportez en Excel\n\n'
        'Je suis là pour vous guider à chaque étape !',
        suggestions: [
          'Créer mon premier examen',
          'Comment scanner les copies ?',
          'Voir le classement',
        ],
      );
    }

    // Bug / problème
    if (_match(t, ['bug', 'erreur', 'probleme', 'plante', 'crash', 'marche pas', 'fonctionne pas'])) {
      return const _BotResponse(
        '🛠️ **Un problème ?**\n'
        'Décrivez-moi précisément ce qui se passe : à quel moment, sur quel écran, quel message d\'erreur ?\n\n'
        'Astuces classiques :\n'
        '• Fermez et rouvrez l\'app\n'
        '• Vérifiez que vous avez assez d\'espace de stockage\n'
        '• Pour le scan : autorisez l\'accès à la caméra dans les paramètres\n'
        '• Pour l\'export : autorisez le partage de fichiers',
      );
    }

    // À propos / qui es-tu
    if (_match(t, ['qui es tu', 'qui etes vous', 'tu es qui', 'about', 'a propos'])) {
      return const _BotResponse(
        '🤖 Je suis **Correctis Chatbot**, l\'assistant intégré à votre application Correctis.\n\n'
        'Mon rôle : vous guider dans la création d\'examens, le scan des copies, la correction IA, et tout le reste. Je peux aussi simplement discuter avec vous si vous voulez !',
      );
    }

    // Discussion générale (encouragements, vie quotidienne)
    if (_match(t, ['fatigue', 'epuise', 'crevé', 'tired'])) {
      return const _BotResponse(
        '😴 La correction des copies prend du temps — c\'est normal d\'être fatigué. C\'est exactement pourquoi Correctis existe : automatiser le plus pénible pour vous laisser le plus important : le pédagogique.\n\nVoulez-vous que je vous aide à finir plus vite ?',
      );
    }
    if (_match(t, ['eleve difficile', 'classe difficile', 'turbulent'])) {
      return const _BotResponse(
        'Je comprends 😔 Avec Correctis vous gagnez du temps sur la correction — ce qui vous laisse plus d\'énergie pour le terrain et l\'humain.',
      );
    }

    // Fallback
    return _BotResponse(
      'Je n\'ai pas tout à fait saisi votre demande 🤔 Mais je peux vous aider avec :',
      suggestions: const [
        'Créer un examen',
        'Scanner les copies',
        'Source de correction',
        'Voir le classement',
        'Exporter en Excel',
        'Modifier mon profil',
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------
  String _normalize(String s) {
    var x = s.toLowerCase().trim();
    // Supprime les accents courants
    const from = 'àâäéèêëîïôöùûüç';
    const to = 'aaaeeeeiioouuuc';
    for (int i = 0; i < from.length; i++) {
      x = x.replaceAll(from[i], to[i]);
    }
    return x;
  }

  bool _match(String text, List<String> keywords) {
    return keywords.any((k) => text.contains(_normalize(k)));
  }
}

class _BotResponse {
  final String text;
  final List<String>? suggestions;
  const _BotResponse(this.text, {this.suggestions});
}
