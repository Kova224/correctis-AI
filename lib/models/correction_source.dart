/// Source de correction (cahier §3.3).
///
/// v3 (juin 2026) :
///   - Le prof peut maintenant fournir CORRIGÉ TYPE et COURS en même temps
///   - L'IA générée reste exclusive (ne se mélange pas avec les documents)
///   - Backward compat avec l'ancien format (un seul tableau `documentPaths`
///     + un `type` indicateur).
enum CorrectionSourceType {
  answerKey, // A — Corrigé type (un ou plusieurs documents)
  course, // B — Cours / support
  aiGenerated, // C — Génération IA (validée par le prof)
}

extension CorrectionSourceTypeX on CorrectionSourceType {
  String get title {
    switch (this) {
      case CorrectionSourceType.answerKey:
        return 'Corrigé type';
      case CorrectionSourceType.course:
        return 'Cours / Support';
      case CorrectionSourceType.aiGenerated:
        return 'Génération IA';
    }
  }

  String get subtitle {
    switch (this) {
      case CorrectionSourceType.answerKey:
        return 'Importer un ou plusieurs documents (photos, images, PDF)';
      case CorrectionSourceType.course:
        return 'L\'IA évalue par rapport à votre cours';
      case CorrectionSourceType.aiGenerated:
        return 'L\'IA propose un corrigé que vous validez';
    }
  }
}

class CorrectionSource {
  /// Type "primaire" — conservé pour rétro-compat (anciennes versions de l'app)
  /// et pour le mode `aiGenerated` qui reste exclusif.
  final CorrectionSourceType type;

  /// Legacy : ancien tableau unique (rempli selon le type primaire).
  /// Nouvelles versions : peut rester vide, on lit `answerKeyPaths` / `coursePaths`.
  final List<String> documentPaths;

  /// NEW v3 — Chemins/URLs des documents du **corrigé type** (cumulable avec course).
  final List<String> answerKeyPaths;

  /// NEW v3 — Chemins/URLs des documents de **cours / support** (cumulable avec answerKey).
  final List<String> coursePaths;

  /// Pour le mode IA : contenu du corrigé généré et validable par le prof.
  final String? generatedContent;

  /// Requis pour le mode `aiGenerated` avant correction (sinon bloquant).
  final bool validated;

  const CorrectionSource({
    required this.type,
    this.documentPaths = const [],
    this.answerKeyPaths = const [],
    this.coursePaths = const [],
    this.generatedContent,
    this.validated = false,
  });

  /// Indique si au moins une source utilisable est présente.
  bool get hasAnyContent =>
      answerKeyPaths.isNotEmpty ||
      coursePaths.isNotEmpty ||
      documentPaths.isNotEmpty ||
      (generatedContent != null && generatedContent!.trim().isNotEmpty);

  /// Renvoie les paths effectifs pour le corrigé type (fusion new + legacy).
  List<String> get effectiveAnswerKeyPaths {
    if (answerKeyPaths.isNotEmpty) return answerKeyPaths;
    if (type == CorrectionSourceType.answerKey) return documentPaths;
    return const [];
  }

  /// Renvoie les paths effectifs pour le cours (fusion new + legacy).
  List<String> get effectiveCoursePaths {
    if (coursePaths.isNotEmpty) return coursePaths;
    if (type == CorrectionSourceType.course) return documentPaths;
    return const [];
  }

  CorrectionSource copyWith({
    CorrectionSourceType? type,
    List<String>? documentPaths,
    List<String>? answerKeyPaths,
    List<String>? coursePaths,
    String? generatedContent,
    bool? validated,
  }) =>
      CorrectionSource(
        type: type ?? this.type,
        documentPaths: documentPaths ?? this.documentPaths,
        answerKeyPaths: answerKeyPaths ?? this.answerKeyPaths,
        coursePaths: coursePaths ?? this.coursePaths,
        generatedContent: generatedContent ?? this.generatedContent,
        validated: validated ?? this.validated,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'documentPaths': documentPaths,
        'answerKeyPaths': answerKeyPaths,
        'coursePaths': coursePaths,
        'generatedContent': generatedContent,
        'validated': validated,
      };

  factory CorrectionSource.fromJson(Map<String, dynamic> json) =>
      CorrectionSource(
        type: CorrectionSourceType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => CorrectionSourceType.answerKey,
        ),
        documentPaths: List<String>.from(json['documentPaths'] ?? const []),
        answerKeyPaths: List<String>.from(json['answerKeyPaths'] ?? const []),
        coursePaths: List<String>.from(json['coursePaths'] ?? const []),
        generatedContent: json['generatedContent'] as String?,
        validated: json['validated'] as bool? ?? false,
      );
}
