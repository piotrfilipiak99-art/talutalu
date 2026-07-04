import 'text_token.dart';

/// One message in a Converse conversation. User messages are plain text;
/// AI messages carry per-word [tokens] (same shape as the reader's
/// TextToken, see text_token.dart) so they can be tapped, checked, and
/// played back exactly like text in the Read tab.
class ChatMessage {
  final String id;
  final bool fromUser;
  final String text;
  final List<TextToken> tokens;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.fromUser,
    required this.text,
    this.tokens = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromUser': fromUser,
        'text': text,
        'tokens': tokens.map((t) => t.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        fromUser: j['fromUser'] as bool,
        text: j['text'] as String,
        tokens: (j['tokens'] as List? ?? [])
            .map((e) =>
                TextToken.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: j['createdAt'] != null
            ? DateTime.parse(j['createdAt'] as String)
            : DateTime.now(),
      );
}
