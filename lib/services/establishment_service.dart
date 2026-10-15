import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/establishment.dart';
import '../models/exam.dart';
import '../models/notification.dart';
import '../screens/admin/admin_models.dart';

/// Service pour la gestion d'un établissement (école/lycée).
///
/// Utilisation :
///   - `currentEstablishment` : l'école dont l'utilisateur est membre (ou null)
///   - `currentMember` : son rôle (admin/teacher)
///   - `isAdmin` : raccourci
///   - `bootstrap()` : à appeler au démarrage/login pour charger les données
class EstablishmentService extends ChangeNotifier {
  static const _kPrefActiveEstabId = 'active_establishment_id';

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  Establishment? _establishment;
  EstablishmentMember? _currentMember;
  List<EstablishmentMember> _members = const [];
  List<EstablishmentInvitation> _pendingInvitations = const [];

  /// Liste de TOUTES les écoles dont l'user est membre (multi-établissement).
  /// Chaque entrée contient l'école + le rôle de l'user dans cette école.
  List<MembershipSummary> _myMemberships = const [];

  Establishment? get currentEstablishment => _establishment;
  EstablishmentMember? get currentMember => _currentMember;
  List<EstablishmentMember> get members => _members;
  List<EstablishmentInvitation> get pendingInvitations => _pendingInvitations;
  List<MembershipSummary> get myMemberships => _myMemberships;

  /// True si l'user appartient à plusieurs écoles.
  bool get hasMultipleMemberships => _myMemberships.length > 1;

  bool get isAdmin => _currentMember?.isAdmin == true;
  bool get isTeacher => _currentMember?.isTeacher == true;
  bool get hasEstablishment => _establishment != null;

  /// Charge l'établissement de l'utilisateur (si membre).
  Future<void> bootstrap() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _establishment = null;
      _currentMember = null;
      _members = const [];
      _pendingInvitations = const [];
      notifyListeners();
      return;
    }

    try {
      // 1. Charge TOUTES les memberships (multi-établissement).
      final memsRes = await _client.rpc('get_my_memberships');
      final memRows = (memsRes as List?) ?? const <dynamic>[];
      _myMemberships = memRows.map<MembershipSummary>((r) {
        final m = r as Map<String, dynamic>;
        return MembershipSummary(
          membershipId: m['out_membership_id'] as String,
          establishmentId: m['out_establishment_id'] as String,
          establishmentName: m['out_establishment_name'] as String? ?? '',
          establishmentCity: m['out_establishment_city'] as String?,
          role: m['out_role'] as String,
          matiere: m['out_matiere'] as String?,
          matieres: (m['out_matieres'] as List?)?.cast<String>() ?? const [],
          classes: (m['out_classes'] as List?)?.cast<String>() ?? const [],
          isActive: m['out_is_active'] as bool? ?? true,
          joinedAt: DateTime.parse(m['out_joined_at'] as String),
        );
      }).where((m) => m.isActive).toList();

      // 2. Choisit l'école active : préférence persistée, sinon la première
      String? activeId;
      try {
        final prefs = await SharedPreferences.getInstance();
        activeId = prefs.getString(_kPrefActiveEstabId);
      } catch (_) {}
      if (activeId == null ||
          !_myMemberships.any((m) => m.establishmentId == activeId)) {
        activeId = _myMemberships.isNotEmpty
            ? _myMemberships.first.establishmentId
            : null;
      }

      if (activeId == null) {
        debugPrint('[EstablishmentService] aucune membership');
        _establishment = null;
        _currentMember = null;
        _members = const [];
        _pendingInvitations = const [];
        notifyListeners();
        return;
      }

      // 3. Charge le détail de l'école active via get_my_membership.
      // FIX Michel : on passe explicitement p_establishment_id = activeId
      // pour que la RPC retourne le BON membership (multi-école).
      final rpcRes = await _client.rpc(
        'get_my_membership',
        params: {'p_establishment_id': activeId},
      );
      final rows = (rpcRes as List?) ?? const <dynamic>[];
      if (rows.isEmpty) {
        // Fallback : reconstruit depuis MembershipSummary
        final summary = _myMemberships
            .firstWhere((m) => m.establishmentId == activeId);
        _establishment = Establishment(
          id: summary.establishmentId,
          name: summary.establishmentName,
          city: summary.establishmentCity,
          plan: 'trial',
          status: 'active',
          ownerId: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _currentMember = EstablishmentMember(
          id: summary.membershipId,
          establishmentId: summary.establishmentId,
          userId: user.id,
          role: summary.role,
          matiere: summary.matiere,
          classes: summary.classes,
          isActive: summary.isActive,
          joinedAt: summary.joinedAt,
        );
        await _loadMembers();
        if (_currentMember!.isAdmin) await _loadInvitations();
        notifyListeners();
        return;
      }

      final row = rows.first as Map<String, dynamic>;
      _currentMember = EstablishmentMember.fromJson({
        'id': row['membership_id'],
        'establishment_id': row['establishment_id'],
        'user_id': row['user_id'],
        'role': row['role'],
        'matiere': row['matiere'],
        'classes': row['classes'],
        'is_active': row['is_active'],
        'joined_at': row['joined_at'],
      });

      _establishment = Establishment.fromJson({
        'id': row['establishment_id'],
        'name': row['establishment_name'],
        'city': row['establishment_city'],
        'country': row['establishment_country'],
        'plan': row['establishment_plan'],
        'status': row['establishment_status'],
        'owner_id': row['establishment_owner_id'],
        'config': row['establishment_config'],
        'created_at': row['establishment_created_at'],
        'updated_at': row['establishment_updated_at'],
      });

      // 2. Charge tous les membres (RLS doit fonctionner pour ça)
      await _loadMembers();

      // 3. Si admin → charge aussi les invitations en attente
      if (_currentMember!.isAdmin) {
        await _loadInvitations();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[EstablishmentService.bootstrap] erreur : $e');
      _establishment = null;
      _currentMember = null;
      _members = const [];
      _pendingInvitations = const [];
      notifyListeners();
    }
  }

  Future<void> _loadMembers() async {
    if (_establishment == null) return;
    try {
      // RPC SECURITY DEFINER pour bypass les RLS récursives.
      final res = await _client.rpc('get_my_establishment_members');
      final rows = (res as List?) ?? const <dynamic>[];
      _members = rows.map<EstablishmentMember>((r) {
        final m = r as Map<String, dynamic>;
        return EstablishmentMember.fromJson({
          'id': m['id'],
          'establishment_id': m['establishment_id'],
          'user_id': m['user_id'],
          'role': m['role'],
          'matiere': m['matiere'],
          'classes': m['classes'],
          'is_active': m['is_active'],
          'joined_at': m['joined_at'],
          'profiles': {
            'display_name': m['display_name'],
            'email': m['email'],
            'photo_path': m['photo_path'],
          },
        });
      }).toList();
    } catch (e) {
      debugPrint('[EstablishmentService._loadMembers] erreur : $e');
      _members = const [];
    }
  }

  Future<void> _loadInvitations() async {
    if (_establishment == null) return;
    try {
      // RPC SECURITY DEFINER pour bypass les RLS récursives.
      final res = await _client.rpc('get_my_pending_invitations');
      final rows = (res as List?) ?? const <dynamic>[];
      _pendingInvitations = rows
          .map<EstablishmentInvitation>((r) =>
              EstablishmentInvitation.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EstablishmentService._loadInvitations] erreur : $e');
      _pendingInvitations = const [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Création d'établissement (au moment de la souscription Phase 2)
  // ─────────────────────────────────────────────────────────────────────────

  /// Crée un établissement et lie l'user comme admin owner.
  /// Michel : passe par une RPC SECURITY DEFINER pour éviter l'erreur
  /// « infinite recursion detected in policy » due aux RLS croisées entre
  /// establishments et establishment_members.
  Future<Establishment> createEstablishment({
    required String name,
    String? city,
    String plan = 'trial',
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw 'Non authentifié';

    final res = await _client.rpc(
      'admin_create_my_establishment',
      params: {
        'p_name': name,
        'p_city': city,
        'p_plan': plan,
      },
    );
    final rows = (res as List?) ?? const <dynamic>[];
    if (rows.isEmpty) throw 'Échec création école (RPC vide).';
    final r = rows.first as Map<String, dynamic>;
    final estab = Establishment.fromJson({
      'id': r['out_id'],
      'name': r['out_name'],
      'city': r['out_city'],
      'plan': r['out_plan'],
      'status': r['out_status'],
      'owner_id': user.id,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await bootstrap();
    return estab;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gestion des invitations (admin only)
  // ─────────────────────────────────────────────────────────────────────────

  /// Invite un enseignant (génère un token + crée la ligne en DB).
  /// L'envoi d'email réel est fait par une Edge Function `send-invitation-email`.
  ///
  /// Retourne un [InviteResult] qui contient l'invitation créée + le statut
  /// d'envoi de l'email (succès / échec avec raison). L'invitation est
  /// toujours créée en DB, même si l'email échoue → l'admin peut renvoyer.
  Future<InviteResult> inviteTeacher({
    required String email,
    String? matiere,
    List<String> classes = const [],
  }) async {
    if (_establishment == null || !isAdmin) {
      throw 'Seul l\'administrateur peut inviter des enseignants.';
    }

    // 1. Création via RPC SECURITY DEFINER (bypass RLS récursives)
    final res = await _client.rpc(
      'create_invitation',
      params: {
        'p_email': email.trim().toLowerCase(),
        'p_matiere': matiere?.trim(),
        'p_classes': classes,
      },
    );
    final rows = (res as List?) ?? const <dynamic>[];
    if (rows.isEmpty) {
      throw 'Création d\'invitation échouée.';
    }
    final invitation =
        EstablishmentInvitation.fromJson(rows.first as Map<String, dynamic>);

    // 2. Envoie l'email via l'Edge Function `send-invitation-email` (Resend).
    final emailResult = await _invokeSendInvitationEmail(invitation.id);

    await _loadInvitations();
    notifyListeners();
    return InviteResult(invitation: invitation, emailResult: emailResult);
  }

  /// Renvoie l'email d'invitation (utile si l'envoi initial a échoué ou
  /// si l'enseignant n'a rien reçu). Retourne le résultat de l'envoi.
  Future<EmailSendResult> resendInvitationEmail(String invitationId) async {
    if (!isAdmin) throw 'Action réservée à l\'administrateur.';
    return _invokeSendInvitationEmail(invitationId);
  }

  /// Appelle l'Edge Function et interprète son résultat de façon explicite.
  Future<EmailSendResult> _invokeSendInvitationEmail(
      String invitationId) async {
    try {
      final response = await _client.functions.invoke(
        'send-invitation-email',
        body: {'invitation_id': invitationId},
      );
      final status = response.status ?? 0;
      final data = response.data;

      if (status >= 200 && status < 300) {
        return const EmailSendResult.success();
      }
      // Erreur retournée par la function (status 4xx/5xx avec un body JSON)
      String? msg;
      if (data is Map && data['error'] is String) {
        msg = data['error'] as String;
      } else if (data != null) {
        msg = data.toString();
      }
      debugPrint(
          '[EstablishmentService] send-invitation-email status=$status data=$data');
      return EmailSendResult.failure(
        'Edge function status $status : ${msg ?? "réponse inattendue"}',
      );
    } catch (e) {
      // Exception réseau ou function introuvable
      debugPrint('[EstablishmentService] invoke échec : $e');
      return EmailSendResult.failure(e.toString());
    }
  }

  /// Annule une invitation en attente (la supprime de la DB).
  Future<void> cancelInvitation(String invitationId) async {
    if (!isAdmin) throw 'Action réservée à l\'administrateur.';
    await _client.rpc(
      'cancel_invitation',
      params: {'p_invitation_id': invitationId},
    );
    await _loadInvitations();
    notifyListeners();
  }

  /// Lookup public d'une invitation par son token. Retourne les infos
  /// nécessaires pour pré-remplir le formulaire d'inscription (email +
  /// nom de l'école) — fonctionne MÊME si l'enseignant n'est pas
  /// encore authentifié.
  ///
  /// Retourne null si le token est inconnu (silencieux pour ne pas
  /// révéler la non-existence d'une invitation).
  Future<InvitationInfo?> lookupInvitationInfo(String token) async {
    try {
      final res = await _client.rpc(
        'get_invitation_info',
        params: {'p_token': token},
      );
      if (res is List && res.isNotEmpty) {
        final row = res.first as Map<String, dynamic>;
        return InvitationInfo(
          email: row['email'] as String? ?? '',
          matiere: row['matiere'] as String?,
          establishmentName: row['establishment_name'] as String? ?? '',
          expired: row['expired'] as bool? ?? false,
          accepted: row['accepted'] as bool? ?? false,
        );
      }
      return null;
    } catch (e) {
      debugPrint('[EstablishmentService] lookup invitation : $e');
      return null;
    }
  }

  /// Accepter une invitation (côté teacher qui clique sur le lien).
  ///
  /// Utilise la RPC `accept_invitation_rpc` SECURITY DEFINER qui fait toute
  /// la séquence côté serveur en bypass des RLS. Garantit que la liaison
  /// admin↔teacher est créée même quand les RLS sur establishment_members
  /// bloqueraient un INSERT direct.
  Future<void> acceptInvitation(String token) async {
    final user = _client.auth.currentUser;
    if (user == null) throw 'Vous devez être connecté pour accepter.';

    final res = await _client.rpc(
      'accept_invitation_rpc',
      params: {'p_token': token},
    );
    // La RPC retourne une liste avec 1 ligne contenant l'établissement
    // rejoint. Si l'opération a échoué côté serveur, l'exception PostgreSQL
    // remonte directement via Supabase.
    final rows = (res as List?) ?? const <dynamic>[];
    if (rows.isEmpty) {
      throw 'L\'acceptation a échoué (réponse vide du serveur).';
    }

    // Recharge tout : currentMember = teacher, establishment = école
    await bootstrap();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Statistiques (admin only)
  // ─────────────────────────────────────────────────────────────────────────

  /// Stats globales de l'établissement (KPIs du Dashboard A1).
  /// Calculées depuis les vraies données : copies graded de tous les teachers.
  Future<EstablishmentStats> computeStats() async {
    if (_establishment == null) return EstablishmentStats.empty();

    try {
      final teacherIds = _members.map((m) => m.userId).toList();
      if (teacherIds.isEmpty) return EstablishmentStats.empty();

      // Compte total des copies graded sur tous les exams des teachers
      final examsRow = await _client
          .from('exams')
          .select('id, total_points, owner_id')
          .filter('owner_id', 'in', '(${teacherIds.join(",")})');

      final examIds =
          (examsRow as List<dynamic>).map((e) => e['id'] as String).toList();
      if (examIds.isEmpty) return EstablishmentStats.empty();

      final copiesRow = await _client
          .from('student_copies')
          .select('id, status, exam_id, general_comment')
          .filter('exam_id', 'in', '(${examIds.join(",")})');

      final copies = copiesRow as List<dynamic>;
      final graded = copies
          .where((c) => (c as Map)['status'] == 'graded')
          .length;
      final flagged = copies.where((c) {
        final comment =
            ((c as Map)['general_comment'] as String?) ?? '';
        return comment.startsWith('⛔ HORS-SUJET — ') ||
            comment.contains('[ZONE_ILLISIBLE]');
      }).length;

      final activeTeachers = _members.where((m) => m.isActive).length;

      return EstablishmentStats(
        totalTeachers: _members.length,
        activeTeachers: activeTeachers,
        totalCopies: copies.length,
        gradedCopies: graded,
        flaggedCopies: flagged,
      );
    } catch (e) {
      debugPrint('[EstablishmentService.computeStats] erreur : $e');
      return EstablishmentStats.empty();
    }
  }

  /// Force le rechargement complet.
  Future<void> refresh() => bootstrap();

  /// Bascule sur une autre école (multi-établissement). Persiste le choix.
  Future<void> switchActiveEstablishment(String establishmentId) async {
    if (!_myMemberships.any((m) => m.establishmentId == establishmentId)) {
      throw 'Vous n\'êtes pas membre de cet établissement.';
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefActiveEstabId, establishmentId);
    } catch (_) {}
    await bootstrap();
  }

  /// Suspend un membre (admin uniquement).
  Future<void> suspendMember(String memberId) async {
    if (!isAdmin) throw 'Action réservée à l\'administrateur.';
    await _client.rpc(
      'suspend_member',
      params: {'p_member_id': memberId},
    );
    await _loadMembers();
    notifyListeners();
  }

  /// Réactive un membre suspendu (admin uniquement).
  Future<void> unsuspendMember(String memberId) async {
    if (!isAdmin) throw 'Action réservée à l\'administrateur.';
    await _client.rpc(
      'unsuspend_member',
      params: {'p_member_id': memberId},
    );
    await _loadMembers();
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Teacher slots (nouveau flow d'invitation Michel)
  // ─────────────────────────────────────────────────────────────────────────

  /// Admin liste tous les slots profs de son école.
  Future<List<TeacherSlot>> loadTeacherSlots() async {
    if (!isAdmin) return const [];
    try {
      final res = await _client.rpc('admin_list_teacher_slots');
      final rows = (res as List?) ?? const <dynamic>[];
      return rows
          .map<TeacherSlot>(
              (r) => TeacherSlot.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EstablishmentService.loadTeacherSlots] $e');
      return const [];
    }
  }

  /// Admin crée un nouveau slot prof.
  Future<void> createTeacherSlot({
    required String schoolEmail,
    required String joinCode,
    required String teacherName,
    List<String> matieres = const [],
  }) async {
    await _client.rpc('admin_create_teacher_slot', params: {
      'p_school_email': schoolEmail,
      'p_join_code': joinCode,
      'p_teacher_name': teacherName,
      'p_matieres': matieres,
    });
    notifyListeners();
  }

  /// Admin met à jour un slot existant.
  Future<void> updateTeacherSlot({
    required String slotId,
    String? teacherName,
    List<String>? matieres,
    String? schoolEmail,
    String? joinCode,
  }) async {
    await _client.rpc('admin_update_teacher_slot', params: {
      'p_slot_id': slotId,
      if (teacherName != null) 'p_teacher_name': teacherName,
      if (matieres != null) 'p_matieres': matieres,
      if (schoolEmail != null) 'p_school_email': schoolEmail,
      if (joinCode != null) 'p_join_code': joinCode,
    });
    notifyListeners();
  }

  /// Admin supprime un slot.
  Future<void> deleteTeacherSlot(String slotId) async {
    await _client.rpc('admin_delete_teacher_slot', params: {
      'p_slot_id': slotId,
    });
    notifyListeners();
  }

  /// Admin suspend / réactive un slot (donc son membership).
  Future<void> toggleSlotStatus({
    required String slotId,
    required String newStatus, // 'pending' | 'claimed' | 'suspended'
  }) async {
    await _client.rpc('admin_toggle_slot_status', params: {
      'p_slot_id': slotId,
      'p_new_status': newStatus,
    });
    notifyListeners();
  }

  /// Prof rejoint une école via email + identifiant.
  /// Retourne une paire (ok, message) pour l'UI.
  Future<TeacherJoinResult> joinSchool({
    required String schoolEmail,
    required String joinCode,
  }) async {
    try {
      final res = await _client.rpc('teacher_join_school', params: {
        'p_school_email': schoolEmail,
        'p_join_code': joinCode,
      });
      final rows = (res as List?) ?? const <dynamic>[];
      if (rows.isEmpty) {
        return const TeacherJoinResult(
            ok: false, reason: 'NO_RESPONSE', message: 'Aucune réponse.');
      }
      final row = rows.first as Map<String, dynamic>;
      final ok = row['out_ok'] as bool? ?? false;
      final reason = (row['out_reason'] ?? '').toString();
      if (!ok) {
        String msg;
        switch (reason) {
          case 'SLOT_NOT_FOUND':
            msg =
                'Email ou identifiant incorrect. Vérifie avec l\'admin de l\'école.';
            break;
          case 'ALREADY_CLAIMED_BY_OTHER':
            msg =
                'Ce compte a déjà été rejoint par un autre utilisateur.';
            break;
          case 'SLOT_SUSPENDED':
            msg =
                'Ce compte est suspendu. Contacte l\'admin de l\'école.';
            break;
          case 'NOT_AUTHENTICATED':
            msg = 'Session expirée. Reconnecte-toi.';
            break;
          case 'TOO_MANY_ATTEMPTS':
            msg =
                'Trop de tentatives incorrectes. Réessaie dans une heure ou demande l\'identifiant exact à l\'admin.';
            break;
          default:
            msg = 'Impossible de joindre : $reason';
        }
        return TeacherJoinResult(ok: false, reason: reason, message: msg);
      }
      // Recharge les memberships pour que "Mes écoles" reflète la nouvelle
      await bootstrap();
      return TeacherJoinResult(
        ok: true,
        reason: 'OK',
        message:
            'Vous avez rejoint ${row['out_establishment_name'] ?? "l\'école"}.',
        establishmentId: row['out_establishment_id'] as String?,
        establishmentName: row['out_establishment_name'] as String?,
      );
    } catch (e) {
      return TeacherJoinResult(
        ok: false,
        reason: 'EXCEPTION',
        message: 'Erreur : $e',
      );
    }
  }

  /// Prof quitte volontairement une école.
  Future<void> leaveSchool(String establishmentId) async {
    await _client.rpc('teacher_leave_school', params: {
      'p_establishment_id': establishmentId,
    });
    await bootstrap();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Config pédagogique (trimestres, coefficients, notifs)
  // ─────────────────────────────────────────────────────────────────────────

  /// Met à jour la configuration pédagogique de l'école. Admin only.
  Future<void> updateConfig(EstablishmentConfig newConfig) async {
    if (_establishment == null || !isAdmin) {
      throw 'Seul l\'administrateur peut modifier la configuration.';
    }
    // RPC SECURITY DEFINER pour bypass les RLS.
    await _client.rpc(
      'update_my_establishment_config',
      params: {'p_config': newConfig.toJson()},
    );
    // Recharge l'établissement depuis le service pour refléter la nouvelle config
    _establishment = Establishment(
      id: _establishment!.id,
      name: _establishment!.name,
      city: _establishment!.city,
      country: _establishment!.country,
      plan: _establishment!.plan,
      status: _establishment!.status,
      ownerId: _establishment!.ownerId,
      config: newConfig,
      createdAt: _establishment!.createdAt,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Casier numérique : toutes les notes des élèves (toutes copies graded)
  // ─────────────────────────────────────────────────────────────────────────

  /// Récupère toutes les notes des copies graded + publiées de l'école.
  ///
  /// Utilise la RPC SECURITY DEFINER `get_school_casier_notes` qui bypass
  /// les RLS récursives. Retourne toutes les notes des élèves envoyées
  /// au casier par les profs de l'école dont je suis admin.
  Future<List<AdminStudentNote>> loadAllNotes() async {
    if (_establishment == null) return const [];
    try {
      final res = await _client.rpc('get_school_casier_notes');
      final rows = (res as List?) ?? const <dynamic>[];
      final result = <AdminStudentNote>[];
      for (final raw in rows) {
        final r = raw as Map<String, dynamic>;
        final score =
            (r['out_total_score'] as num?)?.toDouble() ?? 0.0;
        final total =
            (r['out_exam_total_points'] as num?)?.toDouble() ?? 20.0;
        final note20 = total > 0 ? (score / total) * 20 : score;

        final examTypeCode = r['out_exam_type'] as String?;
        final matiere = examTypeCode != null
            ? ExamType.fromCode(examTypeCode).label
            : ((r['out_exam_title'] as String?) ?? '—');

        final studentRefRaw =
            (r['out_student_ref'] as String?)?.trim();
        final teacherName =
            (r['out_teacher_display_name'] as String?)?.trim().isNotEmpty ==
                    true
                ? r['out_teacher_display_name'] as String
                : ((r['out_teacher_email'] as String?) ?? '—');

        result.add(AdminStudentNote(
          copyId: r['out_copy_id'] as String,
          student:
              (r['out_student_name'] as String?)?.trim().isNotEmpty == true
                  ? r['out_student_name'] as String
                  : 'Sans nom',
          studentRef:
              studentRefRaw?.isNotEmpty == true ? studentRefRaw : null,
          className: (r['out_class_name'] as String?) ?? '—',
          matiere: matiere,
          teacher: teacherName,
          note: double.parse(note20.toStringAsFixed(2)),
          date: DateTime.parse(
              (r['out_copy_published_at'] ?? r['out_copy_created_at'])
                  as String),
          noteLevel: AdminStudentNote.levelFor(note20),
        ));
      }
      return result;
    } catch (e) {
      debugPrint('[EstablishmentService.loadAllNotes] erreur : $e');
      return const [];
    }
  }

  /// Activité récente des profs (notifications dashboard).
  /// Retourne pour chaque prof qui a publié dans les [hours] dernières
  /// heures : son nom, le nombre de notes publiées, la dernière date.
  Future<List<RecentPublication>> loadRecentPublications({
    int hours = 24,
  }) async {
    if (_establishment == null) return const [];
    try {
      final res = await _client.rpc(
        'get_recent_publications',
        params: {'p_hours': hours},
      );
      final rows = (res as List?) ?? const <dynamic>[];
      return rows.map<RecentPublication>((raw) {
        final r = raw as Map<String, dynamic>;
        return RecentPublication(
          teacherUserId: r['out_teacher_user_id'] as String,
          teacherName:
              (r['out_teacher_display_name'] as String?)?.trim().isNotEmpty ==
                      true
                  ? r['out_teacher_display_name'] as String
                  : 'Enseignant',
          count: (r['out_count'] as num?)?.toInt() ?? 0,
          lastPublishedAt:
              DateTime.parse(r['out_last_published_at'] as String),
        );
      }).toList();
    } catch (e) {
      debugPrint(
          '[EstablishmentService.loadRecentPublications] erreur : $e');
      return const [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sprint 2 : Notifications admin → profs
  // ─────────────────────────────────────────────────────────────────────────

  /// Cache local des notifications reçues (pour badge non lu).
  List<AppNotification> _myNotifications = const [];
  List<AppNotification> get myNotifications => _myNotifications;
  int get unreadNotificationsCount =>
      _myNotifications.where((n) => !n.isRead).length;

  /// Recharge les notifications reçues côté prof. À appeler au login + au
  /// pull-to-refresh + à intervalles réguliers depuis la HomeScreen.
  Future<void> loadMyNotifications() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _myNotifications = const [];
      notifyListeners();
      return;
    }
    try {
      final res = await _client.rpc('get_my_notifications');
      final rows = (res as List?) ?? const <dynamic>[];
      _myNotifications = rows
          .map<AppNotification>((r) =>
              AppNotification.fromInbox(r as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[EstablishmentService.loadMyNotifications] erreur : $e');
      _myNotifications = const [];
      notifyListeners();
    }
  }

  /// Marque une notification comme lue (insert idempotent côté DB).
  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _client.rpc(
        'mark_notification_read',
        params: {'p_notification_id': notificationId},
      );
      // Met à jour le cache local
      _myNotifications = _myNotifications.map((n) {
        if (n.id == notificationId && !n.isRead) {
          return AppNotification(
            id: n.id,
            title: n.title,
            body: n.body,
            establishmentName: n.establishmentName,
            authorName: n.authorName,
            createdAt: n.createdAt,
            readAt: DateTime.now(),
          );
        }
        return n;
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[EstablishmentService.markNotificationRead] erreur : $e');
    }
  }

  /// Admin envoie une notification (broadcast si [targets] null/vide,
  /// sinon ciblée sur la liste d'IDs profs).
  Future<String> sendNotification({
    required String title,
    required String body,
    List<String>? targets,
  }) async {
    if (!isAdmin) throw 'Action réservée à l\'administrateur.';
    final res = await _client.rpc(
      'create_notification',
      params: {
        'p_title': title,
        'p_body': body,
        'p_targets':
            (targets == null || targets.isEmpty) ? null : targets,
      },
    );
    return res?.toString() ?? '';
  }

  /// Liste les notifications envoyées par l'admin (avec stats lues/total).
  Future<List<AppNotification>> loadSentNotifications() async {
    if (!isAdmin) return const [];
    try {
      final res = await _client.rpc('get_admin_sent_notifications');
      final rows = (res as List?) ?? const <dynamic>[];
      return rows
          .map<AppNotification>((r) =>
              AppNotification.fromSent(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EstablishmentService.loadSentNotifications] erreur : $e');
      return const [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Sprint 2 : Casier admin groupé par prof → classe → type contrôle
  // ─────────────────────────────────────────────────────────────────────────

  /// Niveau 1 : liste des profs qui ont publié des notes.
  Future<List<TeacherCasierSummary>> loadCasierByTeacher() async {
    if (!isAdmin) return const [];
    try {
      final res = await _client.rpc('get_casier_by_teacher');
      final rows = (res as List?) ?? const <dynamic>[];
      return rows
          .map<TeacherCasierSummary>((r) =>
              TeacherCasierSummary.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EstablishmentService.loadCasierByTeacher] erreur : $e');
      return const [];
    }
  }

  /// Niveau 2 : classes d'un prof avec compte de notes.
  Future<List<TeacherClassSummary>> loadTeacherClasses(
      String teacherUserId) async {
    if (!isAdmin) return const [];
    try {
      final res = await _client.rpc(
        'get_teacher_classes',
        params: {'p_teacher_user_id': teacherUserId},
      );
      final rows = (res as List?) ?? const <dynamic>[];
      return rows
          .map<TeacherClassSummary>((r) =>
              TeacherClassSummary.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EstablishmentService.loadTeacherClasses] erreur : $e');
      return const [];
    }
  }

  /// Niveau 3 : notes d'une classe d'un prof, optionnellement filtrées
  /// par type de contrôle (DS, examen, bac blanc, etc.).
  Future<List<ClassNoteEntry>> loadClassNotes({
    required String teacherUserId,
    required String className,
    String? controlType,
  }) async {
    if (!isAdmin) return const [];
    try {
      final res = await _client.rpc(
        'get_class_notes',
        params: {
          'p_teacher_user_id': teacherUserId,
          'p_class_name': className,
          'p_control_type': controlType,
        },
      );
      final rows = (res as List?) ?? const <dynamic>[];
      return rows
          .map<ClassNoteEntry>((r) =>
              ClassNoteEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EstablishmentService.loadClassNotes] erreur : $e');
      return const [];
    }
  }

  /// Relevé d'un élève par type de contrôle (E - écran élève admin).
  Future<List<StudentReleveEntry>> loadStudentReleve({
    required String studentName,
    String? studentRef,
    String? controlType,
  }) async {
    if (!isAdmin) return const [];
    try {
      final res = await _client.rpc(
        'get_student_releve',
        params: {
          'p_student_name': studentName,
          'p_student_ref': studentRef,
          'p_control_type': controlType,
        },
      );
      final rows = (res as List?) ?? const <dynamic>[];
      return rows
          .map<StudentReleveEntry>((r) =>
              StudentReleveEntry.fromMap(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[EstablishmentService.loadStudentReleve] erreur : $e');
      return const [];
    }
  }

  /// Notes d'un élève spécifique.
  ///
  /// Si [studentRef] est fourni, on filtre strictement par (nom + matricule)
  /// pour éviter les homonymes. Sinon, recherche fuzzy par nom uniquement.
  Future<List<AdminStudentNote>> notesForStudent(
    String studentName, {
    String? studentRef,
  }) async {
    final all = await loadAllNotes();
    final q = studentName.trim().toLowerCase();
    final ref = studentRef?.trim().toLowerCase();
    return all.where((n) {
      final nameMatch = n.student.toLowerCase().contains(q);
      if (!nameMatch) return false;
      if (ref == null || ref.isEmpty) return true;
      return (n.studentRef ?? '').toLowerCase() == ref;
    }).toList();
  }
}

/// Résumé d'une appartenance (school summary) — utilisé pour le switcheur
/// multi-école dans l'app.
class MembershipSummary {
  final String membershipId;
  final String establishmentId;
  final String establishmentName;
  final String? establishmentCity;
  final String role;
  final String? matiere;
  // Michel : matières attribuées par l'admin de cette école
  final List<String> matieres;
  final List<String> classes;
  final bool isActive;
  final DateTime joinedAt;

  const MembershipSummary({
    required this.membershipId,
    required this.establishmentId,
    required this.establishmentName,
    this.establishmentCity,
    required this.role,
    this.matiere,
    this.matieres = const [],
    this.classes = const [],
    this.isActive = true,
    required this.joinedAt,
  });

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';
}

/// Slot prof créé par l'admin (nouveau flow Michel — remplace les tokens).
class TeacherSlot {
  final String slotId;
  final String schoolEmail;
  final String joinCode;
  final String teacherName;
  final List<String> matieres;
  final String status; // 'pending' | 'claimed' | 'suspended'
  final String? claimedByUserId;
  final DateTime? claimedAt;
  final DateTime createdAt;

  const TeacherSlot({
    required this.slotId,
    required this.schoolEmail,
    required this.joinCode,
    required this.teacherName,
    required this.matieres,
    required this.status,
    this.claimedByUserId,
    this.claimedAt,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';
  bool get isClaimed => status == 'claimed';
  bool get isSuspended => status == 'suspended';

  factory TeacherSlot.fromMap(Map<String, dynamic> r) {
    final rawMatieres = r['out_matieres'];
    final matieres = (rawMatieres is List)
        ? rawMatieres.map((e) => e.toString()).toList()
        : <String>[];
    return TeacherSlot(
      slotId: r['out_slot_id']!.toString(),
      schoolEmail: (r['out_school_email'] ?? '').toString(),
      joinCode: (r['out_join_code'] ?? '').toString(),
      teacherName: (r['out_teacher_name'] ?? '').toString(),
      matieres: matieres,
      status: (r['out_status'] ?? 'pending').toString(),
      claimedByUserId: r['out_claimed_by_user_id']?.toString(),
      claimedAt: r['out_claimed_at'] != null
          ? DateTime.tryParse(r['out_claimed_at'].toString())
          : null,
      createdAt: DateTime.tryParse((r['out_created_at'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

/// Résultat du "join school" côté prof.
class TeacherJoinResult {
  final bool ok;
  final String reason;
  final String message;
  final String? establishmentId;
  final String? establishmentName;

  const TeacherJoinResult({
    required this.ok,
    required this.reason,
    required this.message,
    this.establishmentId,
    this.establishmentName,
  });
}

/// Publication récente : un prof X a envoyé Y notes au casier.
class RecentPublication {
  final String teacherUserId;
  final String teacherName;
  final int count;
  final DateTime lastPublishedAt;

  const RecentPublication({
    required this.teacherUserId,
    required this.teacherName,
    required this.count,
    required this.lastPublishedAt,
  });
}

/// Infos publiques d'une invitation (lookup avant authentification).
class InvitationInfo {
  final String email;
  final String? matiere;
  final String establishmentName;
  final bool expired;
  final bool accepted;
  const InvitationInfo({
    required this.email,
    this.matiere,
    required this.establishmentName,
    required this.expired,
    required this.accepted,
  });

  bool get isValid => !expired && !accepted;
}

/// Résultat de l'envoi d'un email.
class EmailSendResult {
  final bool ok;
  final String? errorMessage;

  const EmailSendResult.success()
      : ok = true,
        errorMessage = null;
  const EmailSendResult.failure(String message)
      : ok = false,
        errorMessage = message;
}

/// Résultat d'une invitation : la ligne créée + le statut d'envoi de l'email.
class InviteResult {
  final EstablishmentInvitation invitation;
  final EmailSendResult emailResult;
  const InviteResult({required this.invitation, required this.emailResult});
}

/// Statistiques globales d'un établissement.
class EstablishmentStats {
  final int totalTeachers;
  final int activeTeachers;
  final int totalCopies;
  final int gradedCopies;
  final int flaggedCopies;

  const EstablishmentStats({
    required this.totalTeachers,
    required this.activeTeachers,
    required this.totalCopies,
    required this.gradedCopies,
    required this.flaggedCopies,
  });

  factory EstablishmentStats.empty() => const EstablishmentStats(
        totalTeachers: 0,
        activeTeachers: 0,
        totalCopies: 0,
        gradedCopies: 0,
        flaggedCopies: 0,
      );

  double get gradedRatio =>
      totalCopies == 0 ? 0 : gradedCopies / totalCopies;
}
