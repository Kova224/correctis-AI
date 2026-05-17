import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Une sous-question (a, b, c, 1., 2., …) avec son propre barème.
class SubQuestion {
  final String id;
  String label;       // ex: "a)", "1.", "i)"
  String statement;   // énoncé complet (peut contenir symboles math, formules)
  double points;

  SubQuestion({
    String? id,
    required this.label,
    this.statement = '',
    required this.points,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'statement': statement,
        'points': points,
      };

  factory SubQuestion.fromJson(Map<String, dynamic> json) => SubQuestion(
        id: json['id'] as String?,
        label: json['label'] as String? ?? '',
        statement: json['statement'] as String? ?? '',
        points: (json['points'] as num?)?.toDouble() ?? 0,
      );

  SubQuestion copyWith({
    String? label,
    String? statement,
    double? points,
  }) =>
      SubQuestion(
        id: id,
        label: label ?? this.label,
        statement: statement ?? this.statement,
        points: points ?? this.points,
      );
}

/// Une question ou un exercice du sujet.
///
/// - Si la liste `subQuestions` est vide → c'est une **question simple**
///   notée directement (le champ `points` est utilisé).
/// - Si elle contient des sous-questions → c'est un **exercice** dont la
///   note totale est la somme des sous-questions.
class Question {
  final String id;
  String label;       // ex: "Q1", "Exercice 1"
  String statement;   // énoncé complet de la question/exercice
  double points;      // utilisé seulement si feuille (pas de sub-questions)
  List<SubQuestion> subQuestions;

  Question({
    String? id,
    required this.label,
    this.statement = '',
    this.points = 0,
    List<SubQuestion>? subQuestions,
  })  : id = id ?? _uuid.v4(),
        subQuestions = subQuestions ?? <SubQuestion>[];

  /// Une question est "feuille" si elle n'a pas de sous-questions.
  bool get isLeaf => subQuestions.isEmpty;

  /// Note totale effective : points propres si feuille, sinon somme des sous-questions.
  double get totalPoints =>
      isLeaf ? points : subQuestions.fold<double>(0, (s, q) => s + q.points);

  /// Liste des "leaf IDs" pour la correction IA :
  ///  - `[id]` si la question est feuille
  ///  - `[sub1.id, sub2.id, ...]` sinon
  List<String> get gradableIds =>
      isLeaf ? [id] : subQuestions.map((s) => s.id).toList();

  /// Récupère le barème associé à un leafId donné (id de la question ou d'une sous-question).
  double pointsFor(String leafId) {
    if (isLeaf && id == leafId) return points;
    final sub = subQuestions.where((s) => s.id == leafId).firstOrNull;
    return sub?.points ?? 0;
  }

  /// Récupère le label complet d'un leaf (ex : "Q1" ou "Exercice 1 — a)").
  String labelFor(String leafId) {
    if (isLeaf && id == leafId) return label;
    final sub = subQuestions.where((s) => s.id == leafId).firstOrNull;
    return sub == null ? label : '$label — ${sub.label}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'statement': statement,
        'points': points,
        'subQuestions': subQuestions.map((s) => s.toJson()).toList(),
      };

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'] as String?,
        label: json['label'] as String,
        statement: json['statement'] as String? ?? '',
        points: (json['points'] as num?)?.toDouble() ?? 0,
        subQuestions: (json['subQuestions'] as List<dynamic>? ?? const [])
            .map((e) => SubQuestion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Question copyWith({
    String? label,
    String? statement,
    double? points,
    List<SubQuestion>? subQuestions,
  }) =>
      Question(
        id: id,
        label: label ?? this.label,
        statement: statement ?? this.statement,
        points: points ?? this.points,
        subQuestions: subQuestions ?? this.subQuestions,
      );
}

extension _IterableX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
