enum CopyStatus {
  pending,    // en attente / scan terminé mais pas encore envoyé à l'IA
  processing, // OCR + IA en cours
  graded,     // corrigé
  error,      // erreur de traitement
}

extension CopyStatusX on CopyStatus {
  String get label {
    switch (this) {
      case CopyStatus.pending:
        return 'En attente';
      case CopyStatus.processing:
        return 'Correction en cours';
      case CopyStatus.graded:
        return 'Corrigé';
      case CopyStatus.error:
        return 'Erreur';
    }
  }
}

/// Note attribuée à une question.
class QuestionGrade {
  final String questionId;
  double score;
  String comment;

  QuestionGrade({
    required this.questionId,
    required this.score,
    this.comment = '',
  });

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'score': score,
        'comment': comment,
      };

  factory QuestionGrade.fromJson(Map<String, dynamic> json) => QuestionGrade(
        questionId: json['questionId'] as String,
        score: (json['score'] as num).toDouble(),
        comment: json['comment'] as String? ?? '',
      );
}

/// Une copie élève (multi-pages) + résultat de la correction.
class StudentCopy {
  final String id;
  final String examId;
  String studentName;
  String? studentRef; // PV / matricule
  List<String> pageImages; // chemins locaux des pages scannées (mock)
  CopyStatus status;
  List<QuestionGrade> grades;
  String generalComment;
  double confidence; // 0..1
  DateTime createdAt;
  DateTime? gradedAt;

  StudentCopy({
    required this.id,
    required this.examId,
    required this.studentName,
    this.studentRef,
    List<String>? pageImages,
    this.status = CopyStatus.pending,
    List<QuestionGrade>? grades,
    this.generalComment = '',
    this.confidence = 0,
    DateTime? createdAt,
    this.gradedAt,
  })  : pageImages = pageImages ?? <String>[],
        grades = grades ?? <QuestionGrade>[],
        createdAt = createdAt ?? DateTime.now();

  double get totalScore =>
      grades.fold<double>(0, (sum, g) => sum + g.score);

  Map<String, dynamic> toJson() => {
        'id': id,
        'examId': examId,
        'studentName': studentName,
        'studentRef': studentRef,
        'pageImages': pageImages,
        'status': status.name,
        'grades': grades.map((g) => g.toJson()).toList(),
        'generalComment': generalComment,
        'confidence': confidence,
        'createdAt': createdAt.toIso8601String(),
        'gradedAt': gradedAt?.toIso8601String(),
      };

  factory StudentCopy.fromJson(Map<String, dynamic> json) => StudentCopy(
        id: json['id'] as String,
        examId: json['examId'] as String,
        studentName: json['studentName'] as String,
        studentRef: json['studentRef'] as String?,
        pageImages: List<String>.from(json['pageImages'] ?? const []),
        status: CopyStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => CopyStatus.pending,
        ),
        grades: (json['grades'] as List<dynamic>? ?? const [])
            .map((e) => QuestionGrade.fromJson(e as Map<String, dynamic>))
            .toList(),
        generalComment: json['generalComment'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(json['createdAt'] as String),
        gradedAt: json['gradedAt'] != null
            ? DateTime.parse(json['gradedAt'] as String)
            : null,
      );
}
