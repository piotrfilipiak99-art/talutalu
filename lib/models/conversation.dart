import 'chat_message.dart';

/// A saved Converse chat thread, scoped to one course (base → target
/// language pair), matching how Decks/Flashcards are scoped.
class Conversation {
  final String id;
  final String courseId;
  String? title;
  bool starred;
  List<ChatMessage> messages;
  final DateTime createdAt;

  Conversation({
    required this.id,
    required this.courseId,
    this.title,
    this.starred = false,
    List<ChatMessage>? messages,
    DateTime? createdAt,
  })  : messages = messages ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// Falls back to the first user message when no explicit title is set —
  /// there's no rename UI yet, so this is the only title most threads have.
  String displayTitle() {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    ChatMessage? firstUser;
    for (final m in messages) {
      if (m.fromUser) {
        firstUser = m;
        break;
      }
    }
    if (firstUser == null) return 'New conversation';
    final text = firstUser.text.trim();
    return text.length > 40 ? '${text.substring(0, 40)}…' : text;
  }

  DateTime get lastActivity =>
      messages.isEmpty ? createdAt : messages.last.createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseId': courseId,
        'title': title,
        'starred': starred,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        courseId: j['courseId'] as String,
        title: j['title'] as String?,
        starred: (j['starred'] as bool?) ?? false,
        messages: (j['messages'] as List? ?? [])
            .map((e) =>
                ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: j['createdAt'] != null
            ? DateTime.parse(j['createdAt'] as String)
            : DateTime.now(),
      );
}
