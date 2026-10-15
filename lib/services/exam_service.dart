import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';

import '../config/supabase_config.dart';
import '../models/billing.dart';
import '../models/copy.dart';
import '../models/correction_source.dart';
import '../models/exam.dart';
import '../models/question.dart';
import '../utils/image_resizer.dart';
import '../utils/private_storage.dart';
import '../utils/retry.dart';
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

  // C1 : uploads en cours par copie (pour afficher un badge "envoi..."
  // sur les pages qui ne sont pas encore montées vers Storage).
  final Map<String, Set<String>> _uploadingPathsByCopy = {};

  /// Nombre de pages encore en cours d'upload pour cette copie.
  int uploadingPagesForCopy(String copyId) =>
      _uploadingPathsByCopy[copyId]?.length ?? 0;

  /// True si la page (chemin local) est encore en train d'être uploadée.
  bool isPageUploading(String copyId, String path) =>
      _uploadingPathsByCopy[copyId]?.contains(path) ?? false;

  /// Retourne les examens d'un prof, filtrés par école active si fournie.
  ///
  /// B3 (Sprint 4) — Isolation multi-écoles :
  ///   - Si [activeEstablishmentId] est fourni : ne retourne QUE les examens
  ///     liés à cette école. Les examens "solo" (sans école) sont exclus.
  ///   - Si null : mode legacy — tous les examens du prof (avec ou sans école).
  ///
  /// C'est appelé depuis HomeScreen qui passe l'école active du prof (via
  /// EstablishmentService.currentEstablishment?.id) pour cloisonner l'affichage
  /// des copies entre les écoles.
  List<Exam> examsForUser(String userId, {String? activeEstablishmentId}) =>
      _exams
          .where((e) => e.ownerId == userId)
          .where((e) => activeEstablishmentId == null
              ? true
              : e.establishmentId == activeEstablishmentId)
          .toList()
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

  /// Vide le cache local (déconnexion) pour qu'aucune donnée du compte
  /// précédent ne reste visible si un autre compte se connecte.
  void clearCache() {
    PrivateStorage.clearCache();
    _exams.clear();
    _copies.clear();
    _uploadingPathsByCopy.clear();
    _bootstrapped = false;
    notifyListeners();
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

      // Copies + grades (par batch).
      // B2 : on filtre les copies soft-deleted (deleted_by_prof_at IS NOT NULL)
      // pour qu'elles n'apparaissent plus dans la vue du prof, tout en restant
      // dans le casier admin (via published_at qui reste non-null).
      final examIds = _exams.map((e) => e.id).toList();
      _copies.clear();
      if (examIds.isNotEmpty) {
        final copiesRes = await _client
            .from('student_copies')
            .select('*, question_grades(*)')
            .inFilter('exam_id', examIds)
            .filter('deleted_by_prof_at', 'is', null);
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
    ControlType controlType = ControlType.general,
    String? establishmentId,
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
          'control_type': controlType.code,
          'establishment_id': establishmentId,
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
      'control_type': exam.controlType.code,
      'establishment_id': exam.establishmentId,
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
    // C1 : upload synchrone bloquant. Utilisé pour la validation finale
    // (Terminer cette copie). Pour le scan pages en direct, utiliser plutôt
    // uploadCopyPagesInBackground() qui ne bloque pas l'UI.
    await _uploadCopyPages(copy);

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

  /// C1 — Upload en background des pages locales d'une copie.
  ///
  /// Retourne IMMÉDIATEMENT sans await. Les pages continuent d'être
  /// uploadées en arrière-plan, l'UI n'est pas bloquée.
  /// Le prof peut immédiatement scanner la page suivante.
  ///
  /// Chaque path local en cours d'upload est tracké dans
  /// `_uploadingPathsByCopy[copyId]` pour affichage d'un badge "envoi..."
  /// dans l'UI.
  ///
  /// À la fin de chaque upload individuel :
  ///   - le path local est remplacé par l'URL Storage dans copy.pageImages
  ///   - la copie est persistée en DB (uniquement le champ page_images)
  ///   - notifyListeners() rafraîchit l'UI
  void uploadCopyPagesInBackground(StudentCopy copy) {
    // On identifie tous les paths locaux à uploader.
    final localPaths = copy.pageImages
        .where((p) => !p.startsWith('http://') && !p.startsWith('https://'))
        .toList();
    if (localPaths.isEmpty) return;

    _uploadingPathsByCopy.putIfAbsent(copy.id, () => <String>{}).addAll(localPaths);
    notifyListeners();

    // Lance UNE tâche par page — parallélisme naturel côté serveur.
    for (final localPath in localPaths) {
      unawaited(_uploadOnePageInBackground(copy, localPath));
    }
  }

  Future<void> _uploadOnePageInBackground(
      StudentCopy copy, String localPath) async {
    try {
      final url = await _uploadSinglePage(copy.id, localPath);
      if (url == null) return;

      // Remplace le path local par l'URL dans la copie
      final idx = copy.pageImages.indexOf(localPath);
      if (idx >= 0) {
        copy.pageImages[idx] = url;
      }

      // Persiste uniquement le champ page_images (update ciblé)
      await _client.from('student_copies').update({
        'page_images': copy.pageImages,
      }).eq('id', copy.id);
    } catch (e) {
      debugPrint('[uploadCopyPagesInBackground] échec pour $localPath : $e');
      // On garde le path local dans copy.pageImages — l'upload sera retenté
      // lors de la validation finale de la copie.
    } finally {
      _uploadingPathsByCopy[copy.id]?.remove(localPath);
      if (_uploadingPathsByCopy[copy.id]?.isEmpty ?? false) {
        _uploadingPathsByCopy.remove(copy.id);
      }
      notifyListeners();
    }
  }

  /// Upload une seule page vers Storage. Retourne l'URL publique ou null.
  Future<String?> _uploadSinglePage(String copyId, String localPath) async {
    final resizedPath = await ImageResizer.resizeIfNeeded(localPath);
    final file = File(resizedPath);
    if (!file.existsSync()) return null;
    final dotIdx = resizedPath.lastIndexOf('.');
    final ext = dotIdx >= 0 ? resizedPath.substring(dotIdx) : '.jpg';
    final remotePath =
        '${_userId ?? "anon"}/$copyId/${_uuid.v4()}$ext';
    await RetryHelper.run(
      () => _client.storage
          .from(SupabaseConfig.copiesBucket)
          .upload(remotePath, file),
    );
    return _client.storage
        .from(SupabaseConfig.copiesBucket)
        .getPublicUrl(remotePath);
  }

  /// Upload synchrone des pages locales — utilisé par la validation finale.
  /// Bloque jusqu'à ce que toutes les pages soient uploadées.
  Future<void> _uploadCopyPages(StudentCopy copy) async {
    final remoteImages = <String>[];
    for (final path in copy.pageImages) {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        remoteImages.add(path);
        continue;
      }
      final url = await _uploadSinglePage(copy.id, path);
      if (url != null) {
        remoteImages.add(url);
      } else {
        throw 'Impossible d\'uploader la copie. Vérifiez votre connexion.';
      }
    }
    copy.pageImages
      ..clear()
      ..addAll(remoteImages);
  }

  /// Supprime une copie. Si elle a été publiée au casier admin depuis
  /// Supprime une copie côté prof.
  ///
  /// Comportement selon l'âge de la publication (B2 — Sprint 2) :
  ///   - Copie non publiée OU publiée < 3 jours → suppression physique
  ///     (RPC retourne 'DELETED') : la note disparaît partout.
  ///   - Copie publiée >= 3 jours → soft delete
  ///     (RPC retourne 'ARCHIVED') : la note disparaît de la vue prof
  ///     mais reste dans le casier admin.
  ///
  /// Dans les deux cas, retourne true (l'action a réussi pour le prof).
  /// Le résultat brut ('DELETED' / 'ARCHIVED') est retourné pour permettre
  /// à l'UI d'afficher le bon message.
  Future<String> deleteCopy(String copyId) async {
    final res = await _client.rpc(
      'delete_copy_safe',
      params: {'p_copy_id': copyId},
    );
    final result = res?.toString() ?? 'DELETED';
    // Dans tous les cas OK, on retire la copie de la liste locale.
    _copies.removeWhere((c) => c.id == copyId);
    notifyListeners();
    return result;
  }

  /// Lance la correction asynchrone d'une copie (appelée après "Terminer cette copie").
  ///
  /// [manualCorrections] optionnel : pour le mode Human-in-the-Loop, le prof
  /// peut transcrire les zones illisibles, ce qui est passé à l'Edge Function
  /// grade-copy pour relancer une correction enrichie.
  ///
  /// Gating Pay-as-you-go (grille v5) :
  ///   - Avant la correction, on appelle `reserve_credits(copy_id)` qui débite
  ///     le nombre de crédits correspondant au nombre de pages de la copie
  ///     (1 crédit jusqu'à 8 pages, cf. [CreditRules]) sur le wallet personnel
  ///     ou le pool établissement (FIFO, multi-lots).
  ///   - Relance Human-in-the-Loop ([manualCorrections] non null) : incluse,
  ///     aucun crédit supplémentaire.
  ///   - Si pas assez de crédits ou quota individuel atteint → la copie passe
  ///     en `error` avec un message clair, la correction ne démarre pas.
  ///   - À la fin : le serveur (grade-copy) rend le débit définitif en cas de
  ///     succès, ou rembourse les crédits en cas d'échec technique.
  Future<void> startCorrection(
    String copyId, {
    List<Map<String, dynamic>>? manualCorrections,
    String? activeEstablishmentId,
  }) async {
    final copy = getCopy(copyId);
    if (copy == null) return;
    final exam = getExam(copy.examId);
    if (exam == null) return;

    // ─── Gating crédits ────────────────────────────────────────────────
    // B3 (Sprint 4) : on passe l'école active du prof pour cloisonner
    // strictement les crédits par école (multi-école isolation).
    // Fallback : l'école de rattachement de l'examen si non passée.
    final effectiveEstab = activeEstablishmentId ?? exam.establishmentId;
    final gate = await _tryReserveCredit(
      copy.id,
      effectiveEstab,
      hitl: manualCorrections != null,
    );
    if (!gate.ok) {
      copy.status = CopyStatus.error;
      copy.generalComment = gate.userMessage;
      copy.confidence = 0;
      await updateCopy(copy);
      return;
    }

    copy.status = CopyStatus.processing;
    await updateCopy(copy);
    _updatePollingState();

    // Traitement en arrière-plan
    unawaited(_runCorrection(exam, copy, manualCorrections));
  }

  /// Tente de réserver les crédits de la copie (selon son nombre de pages).
  /// Retourne un résultat lisible pour l'UI.
  /// B3 : passe optionnellement l'école active pour isolation multi-école.
  Future<_CreditGate> _tryReserveCredit(
    String copyId,
    String? establishmentId, {
    bool hitl = false,
  }) async {
    try {
      final res = await _client.rpc(
        'reserve_credits',
        params: {
          'p_copy_id': copyId,
          if (establishmentId != null)
            'p_establishment_id': establishmentId,
          'p_hitl': hitl,
        },
      );
      final rows = (res as List?) ?? const <dynamic>[];
      if (rows.isEmpty) {
        return _CreditGate(
          ok: false,
          reason: 'NO_RESPONSE',
          userMessage:
              '❌ Impossible de réserver un crédit. Réessayez dans un instant.',
        );
      }
      final row = rows.first as Map<String, dynamic>;
      final ok = row['out_ok'] as bool? ?? false;
      final reason = (row['out_reason'] ?? '').toString();
      final credits = (row['out_credits'] as num?)?.toInt() ?? 0;
      final pages = (row['out_pages'] as num?)?.toInt() ?? 0;
      final available = (row['out_available'] as num?)?.toInt() ?? 0;
      if (ok) {
        return _CreditGate(
          ok: true,
          reason: reason,
          userMessage: '',
          credits: credits,
        );
      }
      final need = CreditRules.creditsLabel(credits);
      final pagesTxt = '$pages page${pages > 1 ? 's' : ''}';
      switch (reason) {
        case 'NO_CREDITS':
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Crédits insuffisants : cette copie ($pagesTxt) nécessite $need, il vous en reste $available.',
          );
        case 'QUOTA_EXCEEDED':
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Votre quota individuel est insuffisant : cette copie ($pagesTxt) nécessite $need, il vous en reste $available. Contactez l\'administrateur pour l\'augmenter.',
          );
        case 'UNSUPPORTED_PAGE_FORMAT':
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Cette copie contient un fichier non pris en charge (PDF, Word, HEIC). Rescannez les pages en photo (JPG/PNG).',
          );
        case 'NO_PAGES':
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Aucune page enregistrée pour cette copie. Scannez au moins une page.',
          );
        case 'NOT_MEMBER_OF_ESTABLISHMENT':
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Vous n\'êtes plus membre actif de cette école. Basculez sur une autre école dans votre profil.',
          );
        case 'QUOTA_NOT_SET':
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Aucun crédit ne vous a été attribué par l\'admin de cette école. Contactez-le pour qu\'il vous en donne.',
          );
        case 'NO_CREDITS_IN_POOL':
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Le pool de crédits de cette école est insuffisant pour cette copie ($need). Contactez l\'administrateur de l\'école.',
          );
        default:
          return _CreditGate(
            ok: false,
            reason: reason,
            userMessage:
                '❌ Réservation du crédit refusée ($reason). Contactez le support.',
          );
      }
    } catch (e) {
      debugPrint('[ExamService._tryReserveCredit] $e');
      return _CreditGate(
        ok: false,
        reason: 'EXCEPTION',
        userMessage:
            '❌ Impossible de joindre le service de crédits. Vérifiez votre connexion.',
      );
    }
  }

  /// Confirme la consommation du crédit (succès IA).
  Future<void> _markCreditConsumed(String copyId) async {
    try {
      await _client.rpc('consume_credit', params: {'p_copy_id': copyId});
    } catch (e) {
      debugPrint('[ExamService._markCreditConsumed] $e');
    }
  }

  /// Rembourse les crédits réservés (échec final IA). Idempotent.
  Future<void> _refundCredit(String copyId, String reason) async {
    try {
      await _client.rpc(
        'refund_credits',
        params: {'p_copy_id': copyId, 'p_reason': reason},
      );
    } catch (e) {
      debugPrint('[ExamService._refundCredit] $e');
    }
  }

  Future<void> _runCorrection(
    Exam exam,
    StudentCopy copy,
    List<Map<String, dynamic>>? manualCorrections,
  ) async {
    try {
      debugPrint('[Correction] Appel de grade-copy pour copy=${copy.id}');
      final remote = await _ai.gradeCopyRemote(
        copy.id,
        manualCorrections: manualCorrections,
      );
      if (remote.success) {
        debugPrint('[Correction] grade-copy OK — rechargement DB');
        // Confirme la consommation du crédit (audit propre : passe le txn
        // de 'reserve' à 'consume').
        await _markCreditConsumed(copy.id);
        await _refreshCopyFromDb(copy.id);
        return;
      }

      // L'Edge Function a renvoyé une erreur LOGIQUE (pas une coupure
      // réseau) → on rapporte l'erreur clairement à l'utilisateur ET on
      // rembourse le crédit (l'IA n'a pas pu produire de note).
      debugPrint('[Correction] grade-copy ÉCHEC LOGIQUE : ${remote.error}');
      copy.status = CopyStatus.error;
      copy.generalComment = '❌ Échec de la correction IA : ${remote.error ?? "erreur inconnue"}';
      copy.confidence = 0;
      await updateCopy(copy);
      // Après passage en `error` (exigé côté serveur) : remise en solde des
      // crédits réservés. Idempotent si grade-copy l'a déjà fait.
      await _refundCredit(copy.id, remote.error ?? 'api_error');
    } catch (e) {
      debugPrint('_runCorrection exception (coupure réseau probable): $e');
      // Distinction critique : la correction tourne côté serveur (Edge
      // Function grade-copy). Si le client a juste perdu la connexion ou
      // que l'app a été tuée, l'Edge Function CONTINUE et écrira le
      // résultat directement en DB. On NE marque PAS la copie en erreur
      // pour ne pas effacer ce résultat à venir. La copie reste en
      // `processing` et le polling + le retour foreground récupéreront
      // la note dès qu'elle sera prête.
      //
      // On marque error UNIQUEMENT si l'exception ressemble à une vraie
      // erreur logique (4xx, format invalide…), pas à une coupure réseau.
      final isNetworkLike = e is Exception &&
          (e.toString().contains('SocketException') ||
              e.toString().contains('Failed host lookup') ||
              e.toString().contains('Connection') ||
              e.toString().contains('TimeoutException'));
      if (isNetworkLike) {
        debugPrint(
            '[Correction] coupure réseau — la copie reste en processing.');
        // On essaie tout de même de recharger maintenant au cas où
        // l'Edge Function a déjà fini.
        try {
          await _refreshCopyFromDb(copy.id);
        } catch (_) {}
        return;
      }
      copy.status = CopyStatus.error;
      copy.generalComment = '❌ Échec de la correction IA : $e';
      copy.confidence = 0;
      try {
        await updateCopy(copy);
      } catch (_) {}
    }
  }

  /// Rafraîchit toutes les copies en `processing` ou `error` depuis la DB.
  ///
  /// Stratégie :
  /// - Si la copie était en `processing` côté client → on recharge depuis
  ///   Supabase. L'Edge Function grade-copy écrit directement le résultat
  ///   final en DB, donc si elle a terminé entre-temps (même app fermée),
  ///   on récupère automatiquement le `graded`.
  /// - Si la copie était en `error` à cause d'une coupure réseau → on
  ///   recharge aussi (le serveur peut avoir réussi).
  /// - Si une copie reste en `processing` même après reload ET est ancienne
  ///   (>5 min), on tente une vraie relance.
  ///
  /// Appelée :
  /// - Au retour foreground (via WidgetsBindingObserver)
  /// - Par le polling périodique pendant qu'il y a des copies en cours
  Future<void> refreshProcessingCopies() async {
    final now = DateTime.now();
    for (final exam in _exams) {
      final copies = copiesFor(exam.id);
      for (final c in copies) {
        final isProcessing = c.status == CopyStatus.processing;
        final isErrorNetwork = c.status == CopyStatus.error &&
            (c.generalComment.contains('SocketException') ||
                c.generalComment.contains('Failed host lookup') ||
                c.generalComment.contains('Connection') ||
                c.generalComment.contains('TimeoutException'));
        if (!isProcessing && !isErrorNetwork) continue;

        try {
          await _refreshCopyFromDb(c.id);
        } catch (_) {
          // ignore réseau, on retentera
        }

        // Recharge le statut actuel
        final fresh = getCopy(c.id);
        if (fresh == null) continue;

        // Si toujours en processing depuis plus de 3 min sans réponse
        // serveur → on tente une vraie relance.
        // C2 — Sprint 3 : timeout réduit 5→3 min car avec le prompt caching
        // et images 1400px, une correction doit prendre max ~90s.
        if (fresh.status == CopyStatus.processing) {
          final stuckSince = now.difference(fresh.createdAt);
          if (stuckSince.inMinutes >= 3) {
            debugPrint('[ExamService] copy ${fresh.id} bloquée depuis '
                '${stuckSince.inMinutes} min → relance');
            unawaited(startCorrection(fresh.id));
          }
        }
      }
    }
    _updatePollingState();
  }

  /// Démarre/arrête le polling automatique des copies en cours.
  ///
  /// C2 — Sprint 3 : polling ADAPTATIF selon le nombre de copies en attente.
  ///   - 1-2 copies en attente : polling toutes les 8s
  ///   - 3+ copies en attente : polling toutes les 5s (plus réactif quand
  ///     on lance en batch — utile pour détecter rapidement les fins).
  /// Dès qu'il n'y a plus rien à attendre, le polling s'arrête.
  Timer? _pollTimer;
  int _pollIntervalSecs = 0;
  void _updatePollingState() {
    final pendingCount = _copies.where((c) =>
        c.status == CopyStatus.processing ||
        (c.status == CopyStatus.error &&
            (c.generalComment.contains('SocketException') ||
                c.generalComment.contains('Failed host lookup') ||
                c.generalComment.contains('TimeoutException')))).length;

    if (pendingCount > 0) {
      final targetInterval = pendingCount >= 3 ? 5 : 8;
      if (_pollTimer == null || _pollIntervalSecs != targetInterval) {
        _pollTimer?.cancel();
        _pollIntervalSecs = targetInterval;
        _pollTimer = Timer.periodic(
          Duration(seconds: targetInterval),
          (_) => refreshProcessingCopies(),
        );
        debugPrint(
            '[ExamService] polling actif : $pendingCount copies en cours, intervalle $targetInterval s');
      }
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _pollIntervalSecs = 0;
    }
  }

  /// Recharge une copie depuis la base (après correction par l'Edge Function).
  Future<void> _refreshCopyFromDb(String copyId) async {
    try {
      final row = await _client
          .from('student_copies')
          .select('*, question_grades(*)')
          .eq('id', copyId)
          .single();
      final fresh = _copyFromRow(row);
      final idx = _copies.indexWhere((c) => c.id == copyId);
      if (idx >= 0) {
        _copies[idx] = fresh;
      } else {
        _copies.add(fresh);
      }
      notifyListeners();
      _updatePollingState();
    } catch (e) {
      debugPrint('_refreshCopyFromDb error: $e');
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
      controlType: ControlType.fromCode(row['control_type'] as String?),
      establishmentId: row['establishment_id'] as String?,
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
      publishedAt: row['published_at'] != null
          ? DateTime.parse(row['published_at'] as String)
          : null,
      lockedAt: row['locked_at'] != null
          ? DateTime.parse(row['locked_at'] as String)
          : null,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Publication des notes au casier de l'établissement
  // ─────────────────────────────────────────────────────────────────────────

  /// Envoie toutes les copies graded d'un examen au casier de l'école.
  ///
  /// Passe par la RPC SECURITY DEFINER `publish_exam_copies` pour bypass
  /// les RLS qui sinon bloquent silencieusement l'UPDATE des copies.
  Future<int> publishExamCopies(String examId) async {
    // RPC côté serveur (bypass RLS)
    final res = await _client.rpc(
      'publish_exam_copies',
      params: {'p_exam_id': examId},
    );
    final count = (res is int) ? res : (res is num ? res.toInt() : 0);

    // Met aussi à jour le cache local pour refléter l'état immédiatement
    if (count > 0) {
      final now = DateTime.now();
      for (final c in copiesFor(examId)) {
        if (c.status == CopyStatus.graded && !c.isPublished) {
          c.publishedAt = now;
        }
      }
      notifyListeners();
    }
    return count;
  }

  /// Retire les copies d'un examen du casier (permet au prof de corriger
  /// puis renvoyer plus tard).
  Future<void> unpublishExamCopies(String examId) async {
    await _client.rpc(
      'unpublish_exam_copies',
      params: {'p_exam_id': examId},
    );
    for (final c in copiesFor(examId)) {
      c.publishedAt = null;
    }
    notifyListeners();
  }
}

/// Résultat d'une tentative de réservation de crédit (interne ExamService).
class _CreditGate {
  final bool ok;
  final String reason;
  final String userMessage;

  /// Crédits débités pour la copie (0 si relance HITL incluse).
  final int credits;
  const _CreditGate({
    required this.ok,
    required this.reason,
    required this.userMessage,
    this.credits = 0,
  });
}
