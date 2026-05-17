import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/copy.dart';
import '../models/correction_source.dart';
import '../models/exam.dart';
import '../models/question.dart';
import 'ai_correction_service.dart';

/// Service de gestion des examens et des copies — branché sur Supabase.
///
/// Postgres :
///   exams ← questions ← sub_questions
///   exams ← student_copies ← question_grades
/// Storage :
///   subjects/<user>/<exam>/<page>.jpg
///   copies/<user>/<copy>/<page>.jpg
class ExamService extends ChangeNotifier {
  ExamService(this._ai);

  static const _uuid = Uuid();
  final AiCorrectionService _ai;

  sb.SupabaseClient get _client => sb.Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  // Cache local pour des accès synchrones depuis l'UI
  final List<Exam> _exams = <Exam>[];
  final List<StudentCopy> _copies = <StudentCopy>[];
  bool _bootstrapped = false;

  List<Exam> examsForUser(String userId) =>
      _exams.where((e) => e.ownerId == userId).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Exam? getExam(String examId) {
    try {
      return _exams.firstWhere((e) => e.id == examId);
    } catch (_) {
      return null;
    }
  }

  List<StudentCopy> copiesFor(String examId) =>
      _copies.where((c) => c.examId == examId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  StudentCopy? getCopy(String copyId) {
    try {
      return _copies.firstWhere((c) => c.id == copyId);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Bootstrap : charge tout depuis Supabase
  // ---------------------------------------------------------------------------
  Future<void> bootstrap() async {
    if (_userId == null) return;
    try {
      final examsRes = await _client
          .from('exams')
          .select('*, questions(*, sub_questions(*))')
          .order('updated_at', ascending: false);

      _exams
        ..clear()
        ..addAll((examsRes as List).map((row) => _examFromRow(row as Map<String, dynamic>)));

      // Copies + grades (par batch)
      final examIds = _exams.map((e) => e.id).toList();
      _copies.clear();
      if (examIds.isNotEmpty) {
        final copiesRes = await _client
            .from('student_copies')
            .select('*, question_grades(*)')
            .inFilter('exam_id', examIds);
        _copies.addAll((copiesRes as List)
            .map((row) => _copyFromRow(row as Map<String, dynamic>)));
      }
      _bootstrapped = true;
    } catch (e) {
      debugPrint('ExamService.bootstrap error: $e');
    }
    notifyListeners();
  }

  // ===========================================================================
  // EXAMS — CRUD
  // ===========================================================================
  Future<Exam> createExam({
    required String ownerId,
    required String title,
    String? className,
    double totalPoints = 20,
    ExamLanguage language = ExamLanguage.french,
    ExamType examType = ExamType.general,
  }) async {
    final row = await _client
        .from('exams')
        .insert({
          'owner_id': ownerId,
          'title': title,
          'class_name': className,
          'total_points': totalPoints,
          'language': language.code,
          'exam_type': examType.code,
        })
        .select()
        .single();
    final exam = _examFromRow({...row, 'questions': []});
    _exams.add(exam);
    notifyListeners();
    return exam;
  }

  Future<void> updateExam(Exam exam) async {
    // 1. Met à jour la ligne exam
    await _client.from('exams').update({
      'title': exam.title,
      'class_name': exam.className,
      'total_points': exam.totalPoints,
      'language': exam.language.code,
      'exam_type': exam.examType.code,
      'subject_images': exam.subjectImages,
      'subject_validated': exam.subjectValidated,
      'correction_source': exam.correctionSource?.toJson(),
    }).eq('id', exam.id);

    // 2. Sync questions + sub-questions (replace strategy : delete + reinsert)
    await _client.from('questions').delete().eq('exam_id', exam.id);
    for (int i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      await _client.from('questions').insert({
        'id': q.id,
        'exam_id': exam.id,
        'position': i,
        'label': q.label,
        'statement': q.statement,
        'points': q.points,
      });
      for (int j = 0; j < q.subQuestions.length; j++) {
        final sub = q.subQuestions[j];
        await _client.from('sub_questions').insert({
          'id': sub.id,
          'question_id': q.id,
          'position': j,
          'label': sub.label,
          'statement': sub.statement,
          'points': sub.points,
        });
      }
    }

    // 3. Update du cache local
    final idx = _exams.indexWhere((e) => e.id == exam.id);
    if (idx >= 0) {
      exam.updatedAt = DateTime.now();
      _exams[idx] = exam;
    }
    notifyListeners();
  }

  Future<void> deleteExam(String examId) async {
    await _client.from('exams').delete().eq('id', examId);
    _exams.removeWhere((e) => e.id == examId);
    _copies.removeWhere((c) => c.examId == examId);
    notifyListeners();
  }

  // ===========================================================================
  // COPIES — CRUD + upload images
  // ===========================================================================
  Future<StudentCopy> createCopy({
    required String examId,
    required String studentName,
    String? studentRef,
  }) async {
    final row = await _client
        .from('student_copies')
        .insert({
          'exam_id': examId,
          'student_name': studentName,
          'student_ref': studentRef,
        })
        .select()
        .single();
    final copy = _copyFromRow({...row, 'question_grades': []});
    _copies.add(copy);
    notifyListeners();
    return copy;
  }

  Future<void> updateCopy(StudentCopy copy) async {
    // Upload des images locales vers Storage (si pas encore uploadées)
    final remoteImages = <String>[];
    for (final path in copy.pageImages) {
      if (path.startsWith('http')) {
        remoteImages.add(path);
        continue;
      }
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final dotIdx = path.lastIndexOf('.');
        final ext = dotIdx >= 0 ? path.substring(dotIdx) : '.jpg';
        final remotePath =
            '${_userId ?? "anon"}/${copy.id}/${_uuid.v4()}$ext';
        await _client.storage
            .from(SupabaseConfig.copiesBucket)
            .upload(remotePath, file);
        final url = _client.storage
            .from(SupabaseConfig.copiesBucket)
            .getPublicUrl(remotePath);
        remoteImages.add(url);
      } catch (e) {
        // Fallback : garde le chemin local si l'upload échoue
        remoteImages.add(path);
      }
    }
    copy.pageImages
      ..clear()
      ..addAll(remoteImages);

    // Update de la copie
    await _client.from('student_copies').update({
      'student_name': copy.studentName,
      'student_ref': copy.studentRef,
      'page_images': copy.pageImages,
      'status': copy.status.name,
      'general_comment': copy.generalComment,
      'confidence': copy.confidence,
      'graded_at': copy.gradedAt?.toIso8601String(),
    }).eq('id', copy.id);

    // Sync des grades (replace)
    await _client.from('question_grades').delete().eq('copy_id', copy.id);
    for (final g in copy.grades) {
      await _client.from('question_grades').insert({
        'copy_id': copy.id,
        'leaf_id': g.questionId,
        'score': g.score,
        'comment': g.comment,
      });
    }

    final idx = _copies.indexWhere((c) => c.id == copy.id);
    if (idx >= 0) _copies[idx] = copy;
    notifyListeners();
  }

  Future<void> deleteCopy(String copyId) async {
    await _client.from('student_copies').delete().eq('id', copyId);
    _copies.removeWhere((c) => c.id == copyId);
    notifyListeners();
  }

  /// Lance la correction asynchrone d'une copie (appelée après "Terminer cette copie").
  Future<void> startCorrection(String copyId) async {
    final copy = getCopy(copyId);
    if (copy == null) return;
    final exam = getExam(copy.examId);
    if (exam == null) return;

    copy.status = CopyStatus.processing;
    await updateCopy(copy);

    // Traitement en arrière-plan
    unawaited(_runCorrection(exam, copy));
  }

  Future<void> _runCorrection(Exam exam, StudentCopy copy) async {
    try {
      final res = await _ai.gradeCopy(exam: exam, copy: copy);
      copy.grades
        ..clear()
        ..addAll(res.grades);
      copy.generalComment = res.generalComment;
      copy.confidence = res.confidence;
      copy.status = CopyStatus.graded;
      copy.gradedAt = DateTime.now();
      await updateCopy(copy);
    } catch (_) {
      copy.status = CopyStatus.error;
      await updateCopy(copy);
    }
  }

  // ===========================================================================
  // Mappers : Postgres → Dart models
  // ===========================================================================
  Exam _examFromRow(Map<String, dynamic> row) {
    final questionsList = (row['questions'] as List?) ?? const [];
    final questions = questionsList
        .map((qr) => _questionFromRow(qr as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        // tri par position est implicite via Postgres si demandé, sinon par label
        return a.label.compareTo(b.label);
      });

    return Exam(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String,
      title: row['title'] as String,
      className: row['class_name'] as String?,
      totalPoints: (row['total_points'] as num?)?.toDouble() ?? 20,
      language: ExamLanguage.fromCode(row['language'] as String?),
      examType: ExamType.fromCode(row['exam_type'] as String?),
      subjectImages: List<String>.from(row['subject_images'] ?? const []),
      questions: questions,
      subjectValidated: row['subject_validated'] as bool? ?? false,
      correctionSource: row['correction_source'] != null
          ? CorrectionSource.fromJson(
              Map<String, dynamic>.from(row['correction_source'] as Map))
          : null,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  Question _questionFromRow(Map<String, dynamic> row) {
    final subsList = (row['sub_questions'] as List?) ?? const [];
    final subs = subsList
        .map((sr) => SubQuestion(
              id: sr['id'] as String,
              label: sr['label'] as String,
              statement: sr['statement'] as String? ?? '',
              points: (sr['points'] as num?)?.toDouble() ?? 0,
            ))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return Question(
      id: row['id'] as String,
      label: row['label'] as String,
      statement: row['statement'] as String? ?? '',
      points: (row['points'] as num?)?.toDouble() ?? 0,
      subQuestions: subs,
    );
  }

  StudentCopy _copyFromRow(Map<String, dynamic> row) {
    final gradesList = (row['question_grades'] as List?) ?? const [];
    final grades = gradesList
        .map((g) => QuestionGrade(
              questionId: g['leaf_id'] as String,
              score: (g['score'] as num?)?.toDouble() ?? 0,
              comment: g['comment'] as String? ?? '',
            ))
        .toList();
    return StudentCopy(
      id: row['id'] as String,
      examId: row['exam_id'] as String,
      studentName: row['student_name'] as String,
      studentRef: row['student_ref'] as String?,
      pageImages: List<String>.from(row['page_images'] ?? const []),
      status: CopyStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => CopyStatus.pending,
      ),
      grades: grades,
      generalComment: row['general_comment'] as String? ?? '',
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      gradedAt: row['graded_at'] != null
          ? DateTime.parse(row['graded_at'] as String)
          : null,
    );
  }
}
