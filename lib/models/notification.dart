/// Modèle d'une notification admin → prof (consultable côté prof, géré côté admin).
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String? establishmentName;
  final String? authorName;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Côté admin uniquement
  final List<String>? targets; // null = broadcast
  final int? readCount;
  final int? totalRecipients;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.establishmentName,
    this.authorName,
    this.readAt,
    this.targets,
    this.readCount,
    this.totalRecipients,
  });

  bool get isRead => readAt != null;
  bool get isBroadcast => targets == null || targets!.isEmpty;

  /// Pour les notifications côté prof (RPC get_my_notifications)
  factory AppNotification.fromInbox(Map<String, dynamic> row) {
    return AppNotification(
      id: row['out_id']?.toString() ?? '',
      title: (row['out_title'] ?? '').toString(),
      body: (row['out_body'] ?? '').toString(),
      establishmentName: row['out_establishment_name']?.toString(),
      authorName: row['out_author_name']?.toString(),
      createdAt: DateTime.tryParse(row['out_created_at']?.toString() ?? '') ??
          DateTime.now(),
      readAt: row['out_read_at'] != null
          ? DateTime.tryParse(row['out_read_at'].toString())
          : null,
    );
  }

  /// Pour les notifications côté admin (RPC get_admin_sent_notifications)
  factory AppNotification.fromSent(Map<String, dynamic> row) {
    final raw = row['out_targets'];
    List<String>? tgts;
    if (raw is List) {
      tgts = raw.map((e) => e.toString()).toList();
    }
    return AppNotification(
      id: row['out_id']?.toString() ?? '',
      title: (row['out_title'] ?? '').toString(),
      body: (row['out_body'] ?? '').toString(),
      createdAt: DateTime.tryParse(row['out_created_at']?.toString() ?? '') ??
          DateTime.now(),
      targets: tgts,
      readCount: (row['out_read_count'] as num?)?.toInt() ?? 0,
      totalRecipients: (row['out_total_recipients'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Élément du casier groupé par enseignant (vue admin niveau 1).
class TeacherCasierSummary {
  final String teacherUserId;
  final String teacherName;
  final String? teacherEmail;
  final int notesCount;
  final int classesCount;
  final DateTime? lastPublishedAt;

  TeacherCasierSummary({
    required this.teacherUserId,
    required this.teacherName,
    required this.notesCount,
    required this.classesCount,
    this.teacherEmail,
    this.lastPublishedAt,
  });

  factory TeacherCasierSummary.fromMap(Map<String, dynamic> row) {
    return TeacherCasierSummary(
      teacherUserId: row['out_teacher_user_id']?.toString() ?? '',
      teacherName: (row['out_teacher_name'] ?? 'Enseignant').toString(),
      teacherEmail: row['out_teacher_email']?.toString(),
      notesCount: (row['out_notes_count'] as num?)?.toInt() ?? 0,
      classesCount: (row['out_classes_count'] as num?)?.toInt() ?? 0,
      lastPublishedAt: row['out_last_published_at'] != null
          ? DateTime.tryParse(row['out_last_published_at'].toString())
          : null,
    );
  }
}

/// Élément du casier au niveau 2 : classes d'un prof.
class TeacherClassSummary {
  final String className;
  final int notesCount;
  final List<String> controlTypes;
  final DateTime? lastPublishedAt;

  TeacherClassSummary({
    required this.className,
    required this.notesCount,
    required this.controlTypes,
    this.lastPublishedAt,
  });

  factory TeacherClassSummary.fromMap(Map<String, dynamic> row) {
    final raw = row['out_control_types'];
    final types = (raw is List)
        ? raw.map((e) => e.toString()).toList()
        : <String>[];
    return TeacherClassSummary(
      className: (row['out_class_name'] ?? 'Sans classe').toString(),
      notesCount: (row['out_notes_count'] as num?)?.toInt() ?? 0,
      controlTypes: types,
      lastPublishedAt: row['out_last_published_at'] != null
          ? DateTime.tryParse(row['out_last_published_at'].toString())
          : null,
    );
  }
}

/// Élément du casier au niveau 3 : note individuelle d'un élève dans une classe.
class ClassNoteEntry {
  final String copyId;
  final String studentName;
  final String? studentRef;
  final String examId;
  final String examTitle;
  final String? examType;
  final String controlType;
  final double totalPoints;
  final DateTime? publishedAt;
  final double totalScore;

  ClassNoteEntry({
    required this.copyId,
    required this.studentName,
    required this.examId,
    required this.examTitle,
    required this.controlType,
    required this.totalPoints,
    required this.totalScore,
    this.studentRef,
    this.examType,
    this.publishedAt,
  });

  factory ClassNoteEntry.fromMap(Map<String, dynamic> row) {
    return ClassNoteEntry(
      copyId: row['out_copy_id']?.toString() ?? '',
      studentName: (row['out_student_name'] ?? '').toString(),
      studentRef: row['out_student_ref']?.toString(),
      examId: row['out_exam_id']?.toString() ?? '',
      examTitle: (row['out_exam_title'] ?? '').toString(),
      examType: row['out_exam_type']?.toString(),
      controlType: (row['out_control_type'] ?? 'general').toString(),
      totalPoints: (row['out_exam_total_points'] as num?)?.toDouble() ?? 0,
      totalScore: (row['out_total_score'] as num?)?.toDouble() ?? 0,
      publishedAt: row['out_copy_published_at'] != null
          ? DateTime.tryParse(row['out_copy_published_at'].toString())
          : null,
    );
  }
}

/// Élément du relevé élève par type de contrôle.
class StudentReleveEntry {
  final String copyId;
  final String examTitle;
  final String? examType;
  final String controlType;
  final String? className;
  final String teacherName;
  final double totalPoints;
  final double totalScore;
  final DateTime? publishedAt;

  StudentReleveEntry({
    required this.copyId,
    required this.examTitle,
    required this.controlType,
    required this.teacherName,
    required this.totalPoints,
    required this.totalScore,
    this.examType,
    this.className,
    this.publishedAt,
  });

  factory StudentReleveEntry.fromMap(Map<String, dynamic> row) {
    return StudentReleveEntry(
      copyId: row['out_copy_id']?.toString() ?? '',
      examTitle: (row['out_exam_title'] ?? '').toString(),
      examType: row['out_exam_type']?.toString(),
      controlType: (row['out_control_type'] ?? 'general').toString(),
      className: row['out_class_name']?.toString(),
      teacherName: (row['out_teacher_name'] ?? 'Enseignant').toString(),
      totalPoints: (row['out_exam_total_points'] as num?)?.toDouble() ?? 0,
      totalScore: (row['out_total_score'] as num?)?.toDouble() ?? 0,
      publishedAt: row['out_published_at'] != null
          ? DateTime.tryParse(row['out_published_at'].toString())
          : null,
    );
  }
}
