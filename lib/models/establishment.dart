/// Modèle d'un établissement (école/lycée/université).
class Establishment {
  final String id;
  final String name;
  final String? city;
  final String country;
  final String plan; // 'trial', 'school', 'lycee', 'university'
  final String status; // 'active', 'suspended', 'cancelled'
  final String ownerId;
  final EstablishmentConfig config;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Establishment({
    required this.id,
    required this.name,
    this.city,
    this.country = 'Tunisie',
    required this.plan,
    required this.status,
    required this.ownerId,
    this.config = const EstablishmentConfig(),
    required this.createdAt,
    required this.updatedAt,
  });

  String get planLabel {
    switch (plan) {
      case 'school':
        return 'Petite école';
      case 'lycee':
        return 'Lycée / Collège';
      case 'university':
        return 'Université';
      case 'trial':
      default:
        // Plus de « plan » ni d'essai : l'école achète des packs de crédits.
        return 'Paiement à l\'usage';
    }
  }

  factory Establishment.fromJson(Map<String, dynamic> json) => Establishment(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String?,
        country: json['country'] as String? ?? 'Tunisie',
        plan: json['plan'] as String? ?? 'trial',
        status: json['status'] as String? ?? 'active',
        ownerId: json['owner_id'] as String,
        config: EstablishmentConfig.fromJson(
          (json['config'] as Map<String, dynamic>?) ?? const {},
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

/// Configuration pédagogique d'un établissement.
///
/// Tout est saisi par l'admin de l'école dans l'écran de configuration.
/// Aucune valeur par défaut "magique" — si vide, l'UI propose à l'admin
/// de configurer.
class EstablishmentConfig {
  final List<AcademicTerm> terms;
  final Map<String, double> coefficients; // matière → coefficient
  final EstablishmentNotificationPrefs notifications;

  const EstablishmentConfig({
    this.terms = const [],
    this.coefficients = const {},
    this.notifications = const EstablishmentNotificationPrefs(),
  });

  bool get hasTerms => terms.isNotEmpty;
  bool get hasCoefficients => coefficients.isNotEmpty;

  /// Retourne le terme contenant la date donnée, ou null si hors période.
  AcademicTerm? termForDate(DateTime date) {
    for (final t in terms) {
      if (!date.isBefore(t.start) && !date.isAfter(t.end)) return t;
    }
    return null;
  }

  /// Retourne le coefficient d'une matière (1.0 par défaut si non configuré).
  double coefficientFor(String matiere) =>
      coefficients[matiere] ?? 1.0;

  factory EstablishmentConfig.fromJson(Map<String, dynamic> json) {
    final terms = (json['terms'] as List<dynamic>?)
            ?.map((e) => AcademicTerm.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const <AcademicTerm>[];
    final coefs = <String, double>{};
    final rawCoefs = json['coefficients'] as Map<String, dynamic>?;
    if (rawCoefs != null) {
      rawCoefs.forEach((k, v) {
        if (v is num) coefs[k] = v.toDouble();
      });
    }
    return EstablishmentConfig(
      terms: terms,
      coefficients: coefs,
      notifications: EstablishmentNotificationPrefs.fromJson(
        (json['notifications'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'terms': terms.map((t) => t.toJson()).toList(),
        'coefficients': coefficients,
        'notifications': notifications.toJson(),
      };

  EstablishmentConfig copyWith({
    List<AcademicTerm>? terms,
    Map<String, double>? coefficients,
    EstablishmentNotificationPrefs? notifications,
  }) =>
      EstablishmentConfig(
        terms: terms ?? this.terms,
        coefficients: coefficients ?? this.coefficients,
        notifications: notifications ?? this.notifications,
      );
}

/// Un trimestre / semestre saisi par l'école.
class AcademicTerm {
  final String name; // "Trimestre 1", "Semestre 1", etc.
  final DateTime start;
  final DateTime end;

  const AcademicTerm({
    required this.name,
    required this.start,
    required this.end,
  });

  factory AcademicTerm.fromJson(Map<String, dynamic> json) => AcademicTerm(
        name: json['name'] as String,
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'start': start.toIso8601String().substring(0, 10),
        'end': end.toIso8601String().substring(0, 10),
      };

  bool contains(DateTime d) =>
      !d.isBefore(start) && !d.isAfter(end);
}

/// Préférences globales au niveau établissement (sécurité + notifs).
class EstablishmentNotificationPrefs {
  final bool alerts;
  final bool invitationsReminders;
  final bool anonymousStats;
  final bool confidentialityStrict;
  final bool auditLog;

  const EstablishmentNotificationPrefs({
    this.alerts = true,
    this.invitationsReminders = true,
    this.anonymousStats = false,
    this.confidentialityStrict = true,
    this.auditLog = true,
  });

  factory EstablishmentNotificationPrefs.fromJson(Map<String, dynamic> json) =>
      EstablishmentNotificationPrefs(
        alerts: json['alerts'] as bool? ?? true,
        invitationsReminders:
            json['invitations_reminders'] as bool? ?? true,
        anonymousStats: json['anonymous_stats'] as bool? ?? false,
        confidentialityStrict:
            json['confidentiality_strict'] as bool? ?? true,
        auditLog: json['audit_log'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'alerts': alerts,
        'invitations_reminders': invitationsReminders,
        'anonymous_stats': anonymousStats,
        'confidentiality_strict': confidentialityStrict,
        'audit_log': auditLog,
      };

  EstablishmentNotificationPrefs copyWith({
    bool? alerts,
    bool? invitationsReminders,
    bool? anonymousStats,
    bool? confidentialityStrict,
    bool? auditLog,
  }) =>
      EstablishmentNotificationPrefs(
        alerts: alerts ?? this.alerts,
        invitationsReminders:
            invitationsReminders ?? this.invitationsReminders,
        anonymousStats: anonymousStats ?? this.anonymousStats,
        confidentialityStrict:
            confidentialityStrict ?? this.confidentialityStrict,
        auditLog: auditLog ?? this.auditLog,
      );
}

/// Membre d'un établissement (admin ou teacher).
class EstablishmentMember {
  final String id;
  final String establishmentId;
  final String userId;
  final String role; // 'admin' | 'teacher'
  final String? matiere;
  // Michel : matières multiples attribuées par l'admin (codes ExamType).
  // Le prof ne peut créer/corriger que les examens de ces matières.
  final List<String> matieres;
  final List<String> classes;
  final bool isActive;
  final DateTime joinedAt;

  // Champs joints (depuis profiles)
  final String? displayName;
  final String? email;
  final String? photoPath;

  const EstablishmentMember({
    required this.id,
    required this.establishmentId,
    required this.userId,
    required this.role,
    this.matiere,
    this.matieres = const [],
    this.classes = const [],
    this.isActive = true,
    required this.joinedAt,
    this.displayName,
    this.email,
    this.photoPath,
  });

  bool get isAdmin => role == 'admin';
  bool get isTeacher => role == 'teacher';

  String get displayNameOrEmail =>
      displayName?.isNotEmpty == true ? displayName! : (email ?? '?');

  String get initials {
    final name = displayNameOrEmail.trim();
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory EstablishmentMember.fromJson(Map<String, dynamic> json) {
    // Le profil joint vient sous "profiles" (alias)
    final profile = json['profiles'] as Map<String, dynamic>?;
    return EstablishmentMember(
      id: json['id'] as String,
      establishmentId: json['establishment_id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      matiere: json['matiere'] as String?,
      matieres:
          (json['matieres'] as List<dynamic>?)?.cast<String>() ?? const [],
      classes: (json['classes'] as List<dynamic>?)?.cast<String>() ?? const [],
      isActive: json['is_active'] as bool? ?? true,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      displayName: profile?['display_name'] as String?,
      email: profile?['email'] as String?,
      photoPath: profile?['photo_path'] as String?,
    );
  }
}

/// Invitation à rejoindre un établissement (lien 48h).
class EstablishmentInvitation {
  final String id;
  final String establishmentId;
  final String email;
  final String? matiere;
  final List<String> classes;
  final String token;
  final String invitedBy;
  final DateTime expiresAt;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  const EstablishmentInvitation({
    required this.id,
    required this.establishmentId,
    required this.email,
    this.matiere,
    this.classes = const [],
    required this.token,
    required this.invitedBy,
    required this.expiresAt,
    this.acceptedAt,
    required this.createdAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isAccepted => acceptedAt != null;
  bool get isPending => !isExpired && !isAccepted;

  factory EstablishmentInvitation.fromJson(Map<String, dynamic> json) =>
      EstablishmentInvitation(
        id: json['id'] as String,
        establishmentId: json['establishment_id'] as String,
        email: json['email'] as String,
        matiere: json['matiere'] as String?,
        classes:
            (json['classes'] as List<dynamic>?)?.cast<String>() ?? const [],
        token: json['token'] as String,
        invitedBy: json['invited_by'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        acceptedAt: json['accepted_at'] != null
            ? DateTime.parse(json['accepted_at'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
