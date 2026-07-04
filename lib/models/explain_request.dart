import 'text_token.dart';

/// A "discuss this sentence in Converse" hand-off from the Read tab.
///
/// Carries everything Converse needs to open a new conversation that starts
/// with the AI walking through the sentence: the selected sentence text,
/// its aligned translation when the selection sits inside one sentence,
/// and the selection's tokens with [TextToken.charStart]/[TextToken.charEnd]
/// rebased onto [text] (not the original body) so the sentence stays
/// tap-explorable inside the chat bubble.
class ExplainRequest {
  final String courseId;
  final String text;
  final String? translation;
  final List<TextToken> tokens;

  const ExplainRequest({
    required this.courseId,
    required this.text,
    this.translation,
    this.tokens = const [],
  });
}
