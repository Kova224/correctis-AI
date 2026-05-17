import '../models/copy.dart';
import '../models/exam.dart';

/// Une ligne de classement.
class RankingEntry {
  final int position;        // 1, 2, 3, ...
  final String studentName;
  final String? studentRef;
  final double score;
  final double maxScore;
  final double percent;      // 0..100
  final String? mention;     // ex : "Excellent", "Très bien"
  final CopyStatus status;

  const RankingEntry({
    required this.position,
    required this.studentName,
    this.studentRef,
    required this.score,
    required this.maxScore,
    required this.percent,
    this.mention,
    required this.status,
  });
}

/// Service de calcul du classement.
class RankingService {
  /// Classement pour un examen donné — élèves rangés par note décroissante.
  /// Les copies non corrigées sont placées en bas avec status approprié.
  List<RankingEntry> rankExam(Exam exam, List<StudentCopy> copies) {
    final maxScore =
        exam.computedTotal == 0 ? exam.totalPoints : exam.computedTotal;

    // Sépare les corrigées des non-corrigées
    final graded = copies
        .where((c) => c.status == CopyStatus.graded)
        .toList()
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
    final ungraded =
        copies.where((c) => c.status != CopyStatus.graded).toList();

    final entries = <RankingEntry>[];
    for (int i = 0; i < graded.length; i++) {
      final c = graded[i];
      final pct = maxScore == 0 ? 0.0 : (c.totalScore / maxScore) * 100;
      entries.add(RankingEntry(
        position: i + 1,
        studentName: c.studentName,
        studentRef: c.studentRef,
        score: c.totalScore,
        maxScore: maxScore,
        percent: pct,
        mention: _mentionFor(pct),
        status: c.status,
      ));
    }
    // Ajoute les non-corrigées (sans position)
    for (final c in ungraded) {
      entries.add(RankingEntry(
        position: 0,
        studentName: c.studentName,
        studentRef: c.studentRef,
        score: 0,
        maxScore: maxScore,
        percent: 0,
        status: c.status,
      ));
    }
    return entries;
  }

  /// Classement agrégé par classe sur tous les examens d'un prof.
  /// Les notes sont **moyennées** (en %) sur les exams de la même classe.
  /// Renvoie un Map<className, List<RankingEntry>>.
  Map<String, List<RankingEntry>> rankByClass({
    required List<Exam> exams,
    required Map<String, List<StudentCopy>> copiesByExam, // examId -> copies
  }) {
    // Regroupe les copies par (className, studentName)
    final byClass = <String, Map<String, _StudentAgg>>{};
    for (final exam in exams) {
      final className = (exam.className?.trim().isNotEmpty == true)
          ? exam.className!.trim()
          : 'Sans classe';
      final maxScore =
          exam.computedTotal == 0 ? exam.totalPoints : exam.computedTotal;
      final copies = copiesByExam[exam.id] ?? const [];
      for (final c in copies) {
        if (c.status != CopyStatus.graded) continue;
        if (maxScore == 0) continue;
        final ratio = c.totalScore / maxScore;
        final classMap = byClass.putIfAbsent(className, () => {});
        // On utilise le nom comme clé (et ref si dispo) — fragile mais MVP
        final key = c.studentName.trim().toLowerCase();
        final agg = classMap.putIfAbsent(
          key,
          () => _StudentAgg(
            name: c.studentName.trim(),
            ref: c.studentRef,
          ),
        );
        agg.add(ratio, c.totalScore, maxScore);
      }
    }

    final result = <String, List<RankingEntry>>{};
    byClass.forEach((className, students) {
      final list = students.values.toList()
        ..sort((a, b) => b.averageRatio.compareTo(a.averageRatio));
      final entries = <RankingEntry>[];
      for (int i = 0; i < list.length; i++) {
        final s = list[i];
        final pct = s.averageRatio * 100;
        entries.add(RankingEntry(
          position: i + 1,
          studentName: s.name,
          studentRef: s.ref,
          score: s.averageScoreOnTwenty,
          maxScore: 20, // moyenne ramenée sur 20
          percent: pct,
          mention: _mentionFor(pct),
          status: CopyStatus.graded,
        ));
      }
      result[className] = entries;
    });
    return result;
  }

  String _mentionFor(double pct) {
    if (pct >= 80) return 'Excellent';
    if (pct >= 70) return 'Très bien';
    if (pct >= 60) return 'Bien';
    if (pct >= 50) return 'Passable';
    return 'Insuffisant';
  }
}

class _StudentAgg {
  final String name;
  final String? ref;
  double _sumRatio = 0;
  int _count = 0;

  _StudentAgg({required this.name, this.ref});

  void add(double ratio, double score, double max) {
    _sumRatio += ratio;
    _count++;
  }

  double get averageRatio => _count == 0 ? 0 : _sumRatio / _count;
  double get averageScoreOnTwenty => averageRatio * 20;
}
