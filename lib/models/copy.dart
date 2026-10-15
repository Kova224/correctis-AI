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
  DateTime? publishedAt; // envoi au casier de l'établissement
  DateTime? lockedAt; // = publishedAt + 3 jours, verrouille la suppression

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
    this.publishedAt,
    this.lockedAt,
  })  : pageImages = pageImages ?? <String>[],
        grades = grades ?? <QuestionGrade>[],
        createdAt = createdAt ?? DateTime.now();

  bool get isPublished => publishedAt != null;

  /// True si la copie est verrouillée dans le casier admin (publication
  /// remontant à plus de 3 jours). Dans ce cas, la suppression côté prof
  /// ne touche plus le casier admin.
  bool get isLocked =>
      lockedAt != null && lockedAt!.isBefore(DateTime.now());

  /// Nombre d'heures restantes avant verrouillage (utilisé pour afficher
  /// "Verrouille dans Xh"). Retourne 0 si déjà verrouillé ou pas publié.
  int get hoursUntilLock {
    if (lockedAt == null) return 0;
    final remaining = lockedAt!.difference(DateTime.now());
    return remaining.isNegative ? 0 : remaining.inHours;
  }

  double get totalScore =>
      grades.fold<double>(0, (sum, g) => sum + g.score);

  /// Vrai si la copie a été détectée comme hors-sujet par l'IA.
  bool get isOffTopic =>
      generalComment.startsWith('⛔ HORS-SUJET — ') ||
      generalComment.toLowerCase().contains('hors-sujet');

  /// Vrai si la copie contient au moins une zone illisible signalée par l'IA.
  bool get hasIllegibleZones =>
      generalComment.contains('[ZONE_ILLISIBLE]');

  /// Vrai si la copie est en erreur de traitement.
  bool get hasError => status == CopyStatus.error;

  /// Vrai si la copie nécessite l'attention du prof (à reprendre / corriger
  /// manuellement). Couvre les cas hors-sujet, zones illisibles et erreurs.
  bool get needsReview => isOffTopic || hasIllegibleZones || hasError;

  /// Raison principale pour laquelle la copie doit être reprise.
  /// Retourne null si la copie est OK.
  String? get reviewReason {
    if (isOffTopic) return 'Hors-sujet';
    if (hasIllegibleZones) return 'Zones illisibles';
    if (hasError) return 'Erreur traitement';
    return null;
  }

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
        'publishedAt': publishedAt?.toIso8601String(),
        'lockedAt': lockedAt?.toIso8601String(),
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
        publishedAt: json['publishedAt'] != null
            ? DateTime.parse(json['publishedAt'] as String)
            : null,
        lockedAt: json['lockedAt'] != null
            ? DateTime.parse(json['lockedAt'] as String)
            : null,
      );
}
