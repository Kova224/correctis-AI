/// Type de compte défini au signup (Michel spec §3, §8-3).
/// - teacher : accès aux écrans de correction (Accueil, Examens, Scan, Résultats).
///             Peut être solo ou rejoindre N écoles.
/// - admin   : accès uniquement au dashboard admin (gestion école, profs,
///             crédits, casier). Jamais d'écrans de correction.
enum AccountType {
  teacher,
  admin;

  String get dbValue => this == AccountType.admin ? 'admin' : 'teacher';

  static AccountType fromDb(String? v) =>
      v == 'admin' ? AccountType.admin : AccountType.teacher;
}

class AppUser {
  final String id;
  String email;
  String displayName;
  String? photoPath;
  String? phone;
  String? school;
  final AccountType accountType;

  /// Michel : true dès que l'user a choisi Enseignant/Administrateur au
  /// signup email OU via le picker post Google Sign-In.
  /// false → l'app doit afficher le picker (compte fraîchement créé via
  /// OAuth sans metadata accountType).
  final bool accountTypeConfirmed;

  AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoPath,
    this.phone,
    this.school,
    this.accountType = AccountType.teacher,
    this.accountTypeConfirmed = true,
  });

  bool get isAdminAccount => accountType == AccountType.admin;
  bool get isTeacherAccount => accountType == AccountType.teacher;
  bool get needsAccountTypePick => !accountTypeConfirmed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'photoPath': photoPath,
        'phone': phone,
        'school': school,
        'accountType': accountType.dbValue,
        'accountTypeConfirmed': accountTypeConfirmed,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        photoPath: json['photoPath'] as String?,
        phone: json['phone'] as String?,
        school: json['school'] as String?,
        accountType: AccountType.fromDb(json['accountType'] as String?),
        accountTypeConfirmed:
            json['accountTypeConfirmed'] as bool? ?? true,
      );

  AppUser copyWith({
    String? email,
    String? displayName,
    String? photoPath,
    String? phone,
    String? school,
    AccountType? accountType,
    bool? accountTypeConfirmed,
  }) =>
      AppUser(
        id: id,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        photoPath: photoPath ?? this.photoPath,
        phone: phone ?? this.phone,
        school: school ?? this.school,
        accountType: accountType ?? this.accountType,
        accountTypeConfirmed:
            accountTypeConfirmed ?? this.accountTypeConfirmed,
      );
}
