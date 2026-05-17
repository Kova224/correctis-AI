enum ChatRole { user, bot }

class ChatMessage {
  final String id;
  final ChatRole role;
  String text;
  final DateTime createdAt;
  final List<String>? suggestions; // suggestions de réponse rapide

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? createdAt,
    this.suggestions,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'suggestions': suggestions,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        role: ChatRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => ChatRole.bot,
        ),
        text: json['text'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        suggestions: (json['suggestions'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      );
}
