/// Value-objects partagés par les écrans Admin.
/// Aucun mock ici — uniquement les types utilisés par les widgets.
library;

class AdminKpi {
  final String label;
  final String value;
  final String sub;
  final String deltaText;
  final bool isPositive;
  const AdminKpi({
    required this.label,
    required this.value,
    required this.sub,
    required this.deltaText,
    required this.isPositive,
  });
}

enum AdminAlertSeverity { warning, info, error }

class AdminAlert {
  final AdminAlertSeverity severity;
  final String message;
  const AdminAlert({required this.severity, required this.message});
}

class AdminClass {
  final String name;
  final String sub;
  final double avg;
  final String color; // 'blue', 'green', 'amber'
  const AdminClass({
    required this.name,
    required this.sub,
    required this.avg,
    required this.color,
  });
}

class AdminLacune {
  final String label;
  final int percentage;
  final String severity; // 'high', 'medium', 'low'
  const AdminLacune({
    required this.label,
    required this.percentage,
    required this.severity,
  });
}

class AdminTrendPoint {
  final String month;
  final double value; // 0..1
  const AdminTrendPoint({required this.month, required this.value});
}

/// Note d'élève agrégée pour le casier numérique (A3).
///
/// `studentRef` (matricule) sert d'identifiant unique pour distinguer les
/// homonymes : deux élèves portant le même nom mais ayant des matricules
/// différents sont considérés comme distincts.
class AdminStudentNote {
  final String copyId;
  final String student;
  final String? studentRef; // matricule (peut être null si pas renseigné)
  final String className;
  final String matiere;
  final String teacher;
  final double note; // /20
  final DateTime date;
  final String noteLevel; // 'high' | 'medium' | 'low'

  const AdminStudentNote({
    required this.copyId,
    required this.student,
    this.studentRef,
    required this.className,
    required this.matiere,
    required this.teacher,
    required this.note,
    required this.date,
    required this.noteLevel,
  });

  /// Clef d'unicité : nom + matricule. Deux notes avec la même clef sont
  /// pour le même élève.
  String get studentKey =>
      '${student.toLowerCase().trim()}|${(studentRef ?? "").toLowerCase().trim()}';

  /// Affichage compact "Nom (matricule)" si matricule présent, sinon juste
  /// le nom.
  String get displayLabel => studentRef?.trim().isNotEmpty == true
      ? '$student · ${studentRef!.trim()}'
      : student;

  static String levelFor(double note) {
    if (note >= 14) return 'high';
    if (note >= 10) return 'medium';
    return 'low';
  }
}
