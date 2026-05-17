import 'dart:math';

import '../models/exam.dart';
import '../models/question.dart';

/// Service OCR multilingue — mode démo.
/// En prod : Google Cloud Vision (OCR) + LLM (extraction structurée des questions).
///
/// Le mock simule de manière plausible l'extraction d'un sujet structuré :
/// **exercices** (numérotés) contenant des **sous-questions** (a, b, c…),
/// avec énoncés multilignes incluant symboles, équations, formules.
///
/// IMPORTANT : sans vraie OCR connectée, ce service génère du contenu
/// type. Pour reproduire exactement le sujet d'une photo, il faudra :
///   1) brancher Google Cloud Vision (vraie OCR)
///   2) brancher un LLM (Claude/GPT) pour structurer la sortie
class OcrService {
  /// Extrait les exercices et leur barème d'un sujet importé.
  Future<List<Question>> extractQuestionsFromSubject(
    List<String> imagePaths, {
    ExamLanguage language = ExamLanguage.french,
    ExamType examType = ExamType.general,
  }) async {
    final delay = Duration(
      milliseconds: 1500 + 700 * imagePaths.length.clamp(1, 5),
    );
    await Future.delayed(delay);

    final pageCount = imagePaths.length.clamp(1, 6);
    final rng = Random(_seedFromPaths(imagePaths));

    // Nombre d'exercices : 1 page = 1-2 exos, 2 pages = 2-3, 3+ = 3-5
    final exerciseCount =
        pageCount == 1 ? (1 + rng.nextInt(2)) : (2 + rng.nextInt(pageCount));

    final pool = _exercisePool(language: language, examType: examType);
    final available = List.of(pool);
    final result = <Question>[];

    for (int i = 0; i < exerciseCount; i++) {
      if (available.isEmpty) break;
      final exo = available.removeAt(rng.nextInt(available.length));

      // Si l'exo a des sous-questions définies → on les prend telles quelles
      if (exo.subs.isNotEmpty) {
        final subs = exo.subs.map((s) {
          return SubQuestion(
            label: s.label,
            statement: s.statement,
            points: s.points.toDouble(),
          );
        }).toList();
        result.add(Question(
          label: '${_exerciseWord(language)} ${i + 1}',
          statement: exo.statement,
          subQuestions: subs,
        ));
      } else {
        // Sinon : question simple
        result.add(Question(
          label: '${_questionWord(language)} ${i + 1}',
          statement: exo.statement,
          points: exo.points.toDouble(),
        ));
      }
    }
    return result;
  }

  Future<String> extractTextFromCopy(
    List<String> imagePaths, {
    ExamLanguage language = ExamLanguage.french,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return 'Texte OCR (${language.code}) simulé sur ${imagePaths.length} page(s).';
  }

  // -------------------------------------------------------------------------

  String _exerciseWord(ExamLanguage l) {
    switch (l) {
      case ExamLanguage.english:
        return 'Exercise';
      case ExamLanguage.arabic:
        return 'تمرين';
      case ExamLanguage.spanish:
        return 'Ejercicio';
      case ExamLanguage.german:
        return 'Aufgabe';
      case ExamLanguage.italian:
        return 'Esercizio';
      case ExamLanguage.portuguese:
        return 'Exercício';
      case ExamLanguage.french:
      case ExamLanguage.other:
        return 'Exercice';
    }
  }

  String _questionWord(ExamLanguage l) {
    switch (l) {
      case ExamLanguage.english:
        return 'Question';
      case ExamLanguage.arabic:
        return 'سؤال';
      case ExamLanguage.spanish:
        return 'Pregunta';
      case ExamLanguage.german:
        return 'Frage';
      case ExamLanguage.italian:
        return 'Domanda';
      case ExamLanguage.portuguese:
        return 'Pergunta';
      case ExamLanguage.french:
      case ExamLanguage.other:
        return 'Question';
    }
  }

  int _seedFromPaths(List<String> paths) {
    if (paths.isEmpty) return DateTime.now().millisecond;
    return paths.fold<int>(0, (sum, p) => sum + p.hashCode);
  }

  List<_ExerciseSample> _exercisePool({
    required ExamLanguage language,
    required ExamType examType,
  }) {
    final base = _byLanguage(language);
    return base[examType] ?? base[ExamType.general]!;
  }

  Map<ExamType, List<_ExerciseSample>> _byLanguage(ExamLanguage l) {
    switch (l) {
      case ExamLanguage.english:
        return _en;
      case ExamLanguage.arabic:
        return _ar;
      case ExamLanguage.spanish:
        return _es;
      default:
        return _fr;
    }
  }

  // ====================== FRANÇAIS — banques ======================
  static final Map<ExamType, List<_ExerciseSample>> _fr = {
    ExamType.mathematics: [
      _ExerciseSample(
        statement:
            'On considère la fonction f définie sur ℝ par f(x) = 2x³ − 3x² − 12x + 5.',
        subs: [
          _SubSample('a)', 'Calculer la dérivée f\'(x).', 1.5),
          _SubSample('b)', 'Étudier le signe de f\'(x) sur ℝ.', 2),
          _SubSample('c)', 'Dresser le tableau de variations de f.', 1.5),
          _SubSample('d)', 'Déterminer les coordonnées des extrema locaux.', 1),
        ],
      ),
      _ExerciseSample(
        statement:
            'Soit (uₙ) la suite définie par u₀ = 2 et uₙ₊₁ = (1/2)·uₙ + 3 pour tout n ∈ ℕ.',
        subs: [
          _SubSample('a)', 'Calculer u₁, u₂ et u₃.', 1),
          _SubSample('b)', 'Démontrer par récurrence que uₙ ≤ 6 pour tout n ∈ ℕ.', 2),
          _SubSample('c)', 'Étudier la monotonie de la suite (uₙ).', 1.5),
          _SubSample('d)', 'En déduire que (uₙ) converge et déterminer sa limite.', 1.5),
        ],
      ),
      _ExerciseSample(
        statement:
            'Résoudre dans ℝ l\'équation : ln(x + 2) + ln(x − 1) = ln(2x + 4).',
        subs: [
          _SubSample('a)', 'Donner l\'ensemble de définition.', 1),
          _SubSample('b)', 'Résoudre l\'équation et donner la (les) solution(s).', 2),
        ],
      ),
      _ExerciseSample(
        statement:
            'Dans le plan muni d\'un repère orthonormé (O ; i⃗, j⃗), on considère les points A(2 ; 1), B(−1 ; 4), C(3 ; 5).',
        subs: [
          _SubSample('a)', 'Calculer les coordonnées des vecteurs AB⃗ et AC⃗.', 1),
          _SubSample('b)', 'Calculer le produit scalaire AB⃗ · AC⃗.', 1),
          _SubSample('c)', 'Le triangle ABC est-il rectangle ? Justifier.', 1.5),
          _SubSample('d)', 'Calculer l\'aire du triangle ABC.', 1.5),
        ],
      ),
      _ExerciseSample(
        statement:
            'Calculer l\'intégrale I = ∫₀¹ (3x² + 2x − 1) dx, puis donner une interprétation géométrique.',
        points: 3,
      ),
    ],
    ExamType.sciences: [
      _ExerciseSample(
        statement:
            'On dissout 5,85 g de chlorure de sodium NaCl dans 250 mL d\'eau distillée. Données : M(Na) = 23 g/mol, M(Cl) = 35,5 g/mol.',
        subs: [
          _SubSample('a)', 'Calculer la quantité de matière n(NaCl).', 1),
          _SubSample('b)', 'En déduire la concentration molaire de la solution.', 1.5),
          _SubSample('c)', 'Écrire l\'équation de la dissolution dans l\'eau.', 1),
          _SubSample('d)', 'Calculer la concentration des ions Na⁺ et Cl⁻.', 1.5),
        ],
      ),
      _ExerciseSample(
        statement:
            'Un objet de masse m = 500 g est lâché sans vitesse initiale d\'une hauteur h = 10 m. On prendra g = 9,81 m/s² et on néglige les frottements.',
        subs: [
          _SubSample('a)', 'Calculer l\'énergie potentielle initiale.', 1),
          _SubSample('b)', 'Calculer la vitesse de l\'objet juste avant l\'impact.', 2),
          _SubSample('c)', 'Établir le bilan énergétique entre le départ et l\'arrivée.', 2),
        ],
      ),
      _ExerciseSample(
        statement:
            'On étudie une cellule eucaryote en microscopie électronique.',
        subs: [
          _SubSample('a)', 'Légender le schéma fourni en annexe.', 2),
          _SubSample('b)', 'Décrire le rôle des mitochondries.', 1.5),
          _SubSample('c)', 'Comparer cellule animale et cellule végétale.', 1.5),
        ],
      ),
    ],
    ExamType.literature: [
      _ExerciseSample(
        statement:
            'Lecture analytique d\'un extrait d\'œuvre. Lisez attentivement le texte ci-dessous, puis répondez aux questions.',
        subs: [
          _SubSample('a)', 'Présenter brièvement l\'auteur et le contexte de l\'œuvre.', 2),
          _SubSample('b)', 'Identifier le genre littéraire et justifier.', 1.5),
          _SubSample('c)', 'Relever et analyser trois figures de style significatives.', 3),
          _SubSample('d)', 'Proposer un commentaire personnel argumenté du passage.', 4),
        ],
      ),
      _ExerciseSample(
        statement:
            'Dissertation : "L\'écriture est-elle un acte engagé ?" Vous appuierez votre réflexion sur les œuvres étudiées.',
        points: 8,
      ),
    ],
    ExamType.languages: [
      _ExerciseSample(
        statement:
            'Reading comprehension. Read the following text carefully and answer the questions.',
        subs: [
          _SubSample('a)', 'True or False : justify each answer (5 statements).', 2.5),
          _SubSample('b)', 'Find synonyms in the text for these 5 words.', 1.5),
          _SubSample('c)', 'Answer in your own words : what is the main idea?', 2),
        ],
      ),
      _ExerciseSample(
        statement: 'Grammaire / Conjugaison.',
        subs: [
          _SubSample('a)', 'Mettez les verbes au temps qui convient (10 phrases).', 3),
          _SubSample('b)', 'Transformez les phrases au discours indirect.', 2),
        ],
      ),
      _ExerciseSample(
        statement:
            'Production écrite : rédigez un texte de 200 mots sur le thème : "Les nouvelles technologies au service de l\'éducation".',
        points: 6,
      ),
    ],
    ExamType.history: [
      _ExerciseSample(
        statement:
            'Étude de document : analyse d\'une affiche de propagande de la Première Guerre mondiale.',
        subs: [
          _SubSample('a)', 'Présenter le document (nature, auteur, date, contexte).', 1.5),
          _SubSample('b)', 'Décrire précisément la composition de l\'affiche.', 2),
          _SubSample('c)', 'Analyser les messages explicites et implicites.', 2),
          _SubSample('d)', 'Évaluer la portée historique du document.', 1.5),
        ],
      ),
      _ExerciseSample(
        statement:
            'Question problématisée : "En quoi la Révolution française de 1789 est-elle une rupture politique majeure ?"',
        points: 6,
      ),
    ],
    ExamType.philosophy: [
      _ExerciseSample(
        statement:
            'Sujet de dissertation : "Peut-on être libre sans le savoir ?" Vous traiterez ce sujet en vous appuyant sur les auteurs étudiés.',
        points: 12,
      ),
    ],
    ExamType.economics: [
      _ExerciseSample(
        statement:
            'L\'entreprise X présente le bilan suivant au 31/12/N (voir annexe). Capital : 200 000 €. Résultat : +45 000 €.',
        subs: [
          _SubSample('a)', 'Calculer la rentabilité financière.', 1.5),
          _SubSample('b)', 'Analyser la structure du bilan.', 2),
          _SubSample('c)', 'Proposer des pistes d\'amélioration.', 2.5),
        ],
      ),
    ],
    ExamType.computerScience: [
      _ExerciseSample(
        statement:
            'Algorithmique : on souhaite trouver le maximum d\'un tableau d\'entiers de taille n.',
        subs: [
          _SubSample('a)', 'Écrire l\'algorithme en pseudo-code.', 2),
          _SubSample('b)', 'Donner la complexité temporelle dans le pire cas.', 1),
          _SubSample('c)', 'Proposer une variante récursive.', 2),
        ],
      ),
      _ExerciseSample(
        statement:
            'Base de données : on dispose d\'une table CLIENTS(id, nom, ville) et COMMANDES(id, client_id, montant).',
        subs: [
          _SubSample('a)', 'Écrire la requête SQL listant les clients de Paris.', 1.5),
          _SubSample('b)', 'Total des commandes par client (jointure).', 2),
          _SubSample('c)', 'Top 5 des clients par chiffre d\'affaires.', 2),
        ],
      ),
    ],
    ExamType.arts: [
      _ExerciseSample(
        statement:
            'Étude d\'œuvre : analyse d\'un tableau impressionniste (voir reproduction en annexe).',
        subs: [
          _SubSample('a)', 'Identifier le mouvement et l\'auteur supposé.', 1.5),
          _SubSample('b)', 'Analyser la composition et la palette.', 2.5),
          _SubSample('c)', 'Replacer dans le contexte artistique de l\'époque.', 2),
        ],
      ),
    ],
    ExamType.general: [
      _ExerciseSample(
        statement:
            'Question de cours : définir les notions clés étudiées en classe.',
        subs: [
          _SubSample('a)', 'Définir le premier concept et donner un exemple.', 2),
          _SubSample('b)', 'Définir le deuxième concept et l\'illustrer.', 2),
        ],
      ),
      _ExerciseSample(
        statement:
            'Étude de document fourni en annexe.',
        subs: [
          _SubSample('a)', 'Présenter le document.', 1),
          _SubSample('b)', 'Analyser les éléments principaux.', 2),
          _SubSample('c)', 'Conclure et donner votre avis argumenté.', 2),
        ],
      ),
    ],
  };

  // ====================== ENGLISH ======================
  static final Map<ExamType, List<_ExerciseSample>> _en = {
    ExamType.mathematics: [
      _ExerciseSample(
        statement:
            'Consider the function f defined on ℝ by f(x) = 2x³ − 3x² − 12x + 5.',
        subs: [
          _SubSample('a)', 'Compute f\'(x).', 1.5),
          _SubSample('b)', 'Study the sign of f\'(x).', 2),
          _SubSample('c)', 'Build the variation table of f.', 1.5),
          _SubSample('d)', 'Determine the local extrema.', 1),
        ],
      ),
      _ExerciseSample(
        statement:
            'Compute the integral I = ∫₀¹ (3x² + 2x − 1) dx, and give a geometric interpretation.',
        points: 3,
      ),
    ],
    ExamType.sciences: [
      _ExerciseSample(
        statement:
            'A 500 g object is dropped from height h = 10 m. Take g = 9.81 m/s².',
        subs: [
          _SubSample('a)', 'Compute the initial potential energy.', 1),
          _SubSample('b)', 'Compute the velocity just before impact.', 2),
        ],
      ),
    ],
    ExamType.languages: [
      _ExerciseSample(
        statement: 'Reading comprehension on the attached text.',
        subs: [
          _SubSample('a)', 'True / False (5 statements).', 2.5),
          _SubSample('b)', 'Find synonyms for 5 underlined words.', 1.5),
          _SubSample('c)', 'Main idea (your own words).', 2),
        ],
      ),
    ],
    ExamType.general: [
      _ExerciseSample(
        statement: 'Course definitions and examples.',
        subs: [
          _SubSample('a)', 'Define concept 1 and give an example.', 2),
          _SubSample('b)', 'Define concept 2 and illustrate.', 2),
        ],
      ),
    ],
  };

  // ====================== ARABIC ======================
  static final Map<ExamType, List<_ExerciseSample>> _ar = {
    ExamType.mathematics: [
      _ExerciseSample(
        statement:
            'لتكن الدالة f المعرفة على ℝ بـ f(x) = 2x³ − 3x² − 12x + 5.',
        subs: [
          _SubSample('أ)', 'احسب المشتقة f\'(x).', 1.5),
          _SubSample('ب)', 'ادرس إشارة f\'(x) على ℝ.', 2),
          _SubSample('ج)', 'أنشئ جدول تغيرات f.', 1.5),
        ],
      ),
    ],
    ExamType.general: [
      _ExerciseSample(
        statement: 'سؤال عن المفاهيم الأساسية المدروسة.',
        subs: [
          _SubSample('أ)', 'عرّف المفهوم الأول وأعطِ مثالاً.', 2),
          _SubSample('ب)', 'عرّف المفهوم الثاني وأعطِ مثالاً.', 2),
        ],
      ),
    ],
  };

  // ====================== ESPAÑOL ======================
  static final Map<ExamType, List<_ExerciseSample>> _es = {
    ExamType.mathematics: [
      _ExerciseSample(
        statement:
            'Considera la función f definida en ℝ por f(x) = 2x³ − 3x² − 12x + 5.',
        subs: [
          _SubSample('a)', 'Calcula la derivada f\'(x).', 1.5),
          _SubSample('b)', 'Estudia el signo de f\'(x).', 2),
          _SubSample('c)', 'Construye la tabla de variaciones.', 1.5),
        ],
      ),
    ],
    ExamType.general: [
      _ExerciseSample(
        statement: 'Definiciones y ejemplos del curso.',
        subs: [
          _SubSample('a)', 'Define el concepto 1 y da un ejemplo.', 2),
          _SubSample('b)', 'Define el concepto 2 e ilustra.', 2),
        ],
      ),
    ],
  };
}

class _ExerciseSample {
  final String statement;
  final num points;
  final List<_SubSample> subs;
  const _ExerciseSample({
    required this.statement,
    this.points = 0,
    this.subs = const [],
  });
}

class _SubSample {
  final String label;
  final String statement;
  final num points;
  const _SubSample(this.label, this.statement, this.points);
}
