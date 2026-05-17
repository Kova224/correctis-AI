class AppUser {
  final String id;
  String email;
  String displayName;
  String? photoPath;
  String? phone;
  String? school;

  AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoPath,
    this.phone,
    this.school,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'photoPath': photoPath,
        'phone': phone,
        'school': school,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        photoPath: json['photoPath'] as String?,
        phone: json['phone'] as String?,
        school: json['school'] as String?,
      );

  AppUser copyWith({
    String? email,
    String? displayName,
    String? photoPath,
    String? phone,
    String? school,
  }) =>
      AppUser(
        id: id,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        photoPath: photoPath ?? this.photoPath,
        phone: phone ?? this.phone,
        school: school ?? this.school,
      );
}
