import 'correction_source.dart';
import 'question.dart';

/// Langue de l'examen (cf. cahier — l'app doit être multilingue).
enum ExamLanguage {
  french('fr', 'Français', '🇫🇷'),
  english('en', 'English', '🇬🇧'),
  arabic('ar', 'العربية', '🇸🇦'),
  spanish('es', 'Español', '🇪🇸'),
  german('de', 'Deutsch', '🇩🇪'),
  italian('it', 'Italiano', '🇮🇹'),
  portuguese('pt', 'Português', '🇵🇹'),
  other('other', 'Autre', '🌍');

  final String code;
  final String label;
  final String flag;
  const ExamLanguage(this.code, this.label, this.flag);

  static ExamLanguage fromCode(String? code) =>
      ExamLanguage.values.firstWhere(
        (l) => l.code == code,
        orElse: () => ExamLanguage.french,
      );
}

/// Type/discipline (impacte la qualité de l'extraction et de la correction IA).
enum ExamType {
  general('general', 'Général', '📘'),
  mathematics('math', 'Mathématiques', '📐'),
  sciences('sciences', 'Sciences (Physique, Chimie, Bio)', '🔬'),
  literature('literature', 'Littérature / Lettres', '📖'),
  languages('languages', 'Langues', '🗣️'),
  history('history', 'Histoire / Géographie', '🏛️'),
  philosophy('philosophy', 'Philosophie', '💭'),
  economics('economics', 'Économie / Gestion', '📊'),
  computerScience('cs', 'Informatique', '💻'),
  arts('arts', 'Arts', '🎨');

  final String code;
  final String label;
  final String emoji;
  const ExamType(this.code, this.label, this.emoji);

  static ExamType fromCode(String? code) =>
      ExamType.values.firstWhere(
        (t) => t.code == code,
        orElse: () => ExamType.general,
      );
}

class Exam {
  final String id;
  final String ownerId;
  String title;
  String? className;
  double totalPoints;
  ExamLanguage language;
  ExamType examType;
  List<String> subjectImages; // pages du sujet importé
  List<Question> questions;
  bool subjectValidated;
  CorrectionSource? correctionSource;
  DateTime createdAt;
  DateTime updatedAt;

  Exam({
    required this.id,
    required this.ownerId,
    required this.title,
    this.className,
    this.totalPoints = 20,
    this.language = ExamLanguage.french,
    this.examType = ExamType.general,
    List<String>? subjectImages,
    List<Question>? questions,
    this.subjectValidated = false,
    this.correctionSource,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : subjectImages = subjectImages ?? <String>[],
        questions = questions ?? <Question>[],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Note totale calculée à partir des points des questions
  /// (somme des `totalPoints` de chaque question — qui prennent en compte
  ///  les sous-questions s'il y en a).
  double get computedTotal =>
      questions.fold<double>(0, (sum, q) => sum + q.totalPoints);

  /// Liste de tous les "leaf IDs" pour le grading
  /// (chaque ID correspond à un élément notable : question simple OU sous-question).
  List<String> get allGradableIds =>
      questions.expand((q) => q.gradableIds).toList();

  bool get isReadyForScan {
    if (!subjectValidated) return false;
    if (correctionSource == null) return false;
    if (correctionSource!.type == CorrectionSourceType.aiGenerated &&
        !correctionSource!.validated) {
      return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ownerId': ownerId,
        'title': title,
        'className': className,
        'totalPoints': totalPoints,
        'language': language.code,
        'examType': examType.code,
        'subjectImages': subjectImages,
        'questions': questions.map((q) => q.toJson()).toList(),
        'subjectValidated': subjectValidated,
        'correctionSource': correctionSource?.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory Exam.fromJson(Map<String, dynamic> json) => Exam(
        id: json['id'] as String,
        ownerId: json['ownerId'] as String,
        title: json['title'] as String,
        className: json['className'] as String?,
        totalPoints: (json['totalPoints'] as num?)?.toDouble() ?? 20,
        language: ExamLanguage.fromCode(json['language'] as String?),
        examType: ExamType.fromCode(json['examType'] as String?),
        subjectImages: List<String>.from(json['subjectImages'] ?? const []),
        questions: (json['questions'] as List<dynamic>? ?? const [])
            .map((e) => Question.fromJson(e as Map<String, dynamic>))
            .toList(),
        subjectValidated: json['subjectValidated'] as bool? ?? false,
        correctionSource: json['correctionSource'] != null
            ? CorrectionSource.fromJson(
                json['correctionSource'] as Map<String, dynamic>)
            : null,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}
