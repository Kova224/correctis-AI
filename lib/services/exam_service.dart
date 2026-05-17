import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/copy.dart';
import '../models/exam.dart';
import 'ai_correction_service.dart';

/// Service de gestion des examens et des copies.
/// En mode démo : persistance locale via SharedPreferences.
/// En prod : Firestore (collections users / exams / students / copies).
class ExamService extends ChangeNotifier {
  static const _kExamsKey = 'correctis.exams';
  static const _kCopiesKey = 'correctis.copies';

  final AiCorrectionService _ai;
  final List<Exam> _exams = <Exam>[];
  final List<StudentCopy> _copies = <StudentCopy>[];
  bool _bootstrapped = false;

  ExamService(this._ai);

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

  Future<void> bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final prefs = await SharedPreferences.getInstance();
    final examsRaw = prefs.getString(_kExamsKey);
    if (examsRaw != null) {
      final list = jsonDecode(examsRaw) as List<dynamic>;
      _exams
        ..clear()
        ..addAll(list.map((e) => Exam.fromJson(e as Map<String, dynamic>)));
    }
    final copiesRaw = prefs.getString(_kCopiesKey);
    if (copiesRaw != null) {
      final list = jsonDecode(copiesRaw) as List<dynamic>;
      _copies
        ..clear()
        ..addAll(
            list.map((e) => StudentCopy.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  // --- Examens ---
  Future<Exam> createExam({
    required String ownerId,
    required String title,
    String? className,
    double totalPoints = 20,
    ExamLanguage language = ExamLanguage.french,
    ExamType examType = ExamType.general,
  }) async {
    final exam = Exam(
      id: const Uuid().v4(),
      ownerId: ownerId,
      title: title,
      className: className,
      totalPoints: totalPoints,
      language: language,
      examType: examType,
    );
    _exams.add(exam);
    await _persistExams();
    notifyListeners();
    return exam;
  }

  Future<void> updateExam(Exam exam) async {
    final idx = _exams.indexWhere((e) => e.id == exam.id);
    if (idx >= 0) {
      exam.updatedAt = DateTime.now();
      _exams[idx] = exam;
      await _persistExams();
      notifyListeners();
    }
  }

  Future<void> deleteExam(String examId) async {
    _exams.removeWhere((e) => e.id == examId);
    _copies.removeWhere((c) => c.examId == examId);
    await _persistExams();
    await _persistCopies();
    notifyListeners();
  }

  // --- Copies ---
  Future<StudentCopy> createCopy({
    required String examId,
    required String studentName,
    String? studentRef,
  }) async {
    final copy = StudentCopy(
      id: const Uuid().v4(),
      examId: examId,
      studentName: studentName,
      studentRef: studentRef,
    );
    _copies.add(copy);
    await _persistCopies();
    notifyListeners();
    return copy;
  }

  Future<void> updateCopy(StudentCopy copy) async {
    final idx = _copies.indexWhere((c) => c.id == copy.id);
    if (idx >= 0) {
      _copies[idx] = copy;
      await _persistCopies();
      notifyListeners();
    }
  }

  Future<void> deleteCopy(String copyId) async {
    _copies.removeWhere((c) => c.id == copyId);
    await _persistCopies();
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

    // Traitement en arrière-plan (sans bloquer l'UI)
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

  // --- persistance ---
  Future<void> _persistExams() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kExamsKey,
      jsonEncode(_exams.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistCopies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kCopiesKey,
      jsonEncode(_copies.map((c) => c.toJson()).toList()),
    );
  }
}
