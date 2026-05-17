/// Source de correction (cahier §3.3 — choix unique entre 3 modes).
enum CorrectionSourceType {
  answerKey,    // A — Corrigé type (un ou plusieurs documents)
  course,       // B — Cours / support
  aiGenerated,  // C — Génération IA (validée par le prof)
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
  final CorrectionSourceType type;
  final List<String> documentPaths; // chemins locaux ou URLs (mock)
  final String? generatedContent;   // pour le mode IA, contenu validable
  final bool validated;             // requis pour mode aiGenerated avant correction

  const CorrectionSource({
    required this.type,
    this.documentPaths = const [],
    this.generatedContent,
    this.validated = false,
  });

  CorrectionSource copyWith({
    CorrectionSourceType? type,
    List<String>? documentPaths,
    String? generatedContent,
    bool? validated,
  }) =>
      CorrectionSource(
        type: type ?? this.type,
        documentPaths: documentPaths ?? this.documentPaths,
        generatedContent: generatedContent ?? this.generatedContent,
        validated: validated ?? this.validated,
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'documentPaths': documentPaths,
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
        generatedContent: json['generatedContent'] as String?,
        validated: json['validated'] as bool? ?? false,
      );
}
