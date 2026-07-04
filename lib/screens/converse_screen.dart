import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/app_storage.dart';
import '../models/conversation.dart';
import '../models/chat_message.dart';
import '../models/explain_request.dart';
import '../models/text_token.dart';
import '../models/flashcard.dart';
import '../data/alphabet_data.dart';
import '../widgets/word_attributes.dart';

String _ttsLocaleFor(String code) =>
    alphabetFor(code)?.ttsLocale ?? '$code-${code.toUpperCase()}';

/// One renderable chunk of an AI bubble: a word token plus any punctuation
/// tokens that hug it in the source text (charStart == previous charEnd).
/// Without this merge, Wrap's spacing would put a gap before ".", "?" etc.,
/// since the AI tokenizes punctuation separately.
class _TokenGroup {
  _TokenGroup(this.token) : trail = '', _end = token.charEnd;
  final TextToken token;
  String trail;
  int _end;
}

final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Punctuation by content, not by tag — the model sometimes labels "." or
/// "!" with pos "." instead of "PUNCT", which used to leak gaps back in.
bool _isPunctSurface(String surface) => !_letterOrDigit.hasMatch(surface);

List<_TokenGroup> _groupTokens(List<TextToken> tokens) {
  final groups = <_TokenGroup>[];
  for (final t in tokens) {
    if (_isPunctSurface(t.surface) &&
        groups.isNotEmpty &&
        t.charStart == groups.last._end) {
      groups.last.trail += t.surface;
      groups.last._end = t.charEnd;
    } else {
      groups.add(_TokenGroup(t));
    }
  }
  return groups;
}

String _posLabel(String pos) => switch (pos) {
      'NOUN' => 'noun',
      'PROPN' => 'proper noun',
      'VERB' => 'verb',
      'ADJ' => 'adjective',
      'ADV' => 'adverb',
      'NUM' => 'numeral',
      'PRON' => 'pronoun',
      'ADP' => 'preposition',
      'CCONJ' || 'SCONJ' => 'conjunction',
      'PART' => 'particle',
      'DET' => 'determiner',
      'INTJ' => 'interjection',
      _ => pos.toLowerCase(),
    };

String _fmtTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

// ─── Mock AI replies ────────────────────────────────────────────────────────
// Stands in for a real AI generation call (same "mock now, same shape
// later" approach as the Read tab's mock text). Canned, word-annotated
// Polish sentences the chat cycles through so the tap/check/speak UX can be
// exercised end to end without a backend.

class _MockWord {
  final String lemma;
  final String pos;
  final String? translation;
  final String? lemmaTranslation;
  final Map<String, String> morph;
  const _MockWord(this.lemma, this.pos,
      {this.translation, this.lemmaTranslation, this.morph = const {}});
}

class _MockReply {
  final String text;
  final List<_MockWord> words;
  const _MockReply(this.text, this.words);
}

const _mockReplies = [
  _MockReply('Cześć! Miło Cię poznać.', [
    _MockWord('cześć', 'INTJ', translation: 'hi', lemmaTranslation: 'hi'),
    _MockWord('miło', 'ADV', translation: 'nice', lemmaTranslation: 'nicely'),
    _MockWord('ty', 'PRON',
        translation: 'you', lemmaTranslation: 'you', morph: {'Case': 'Acc'}),
    _MockWord('poznać', 'VERB',
        translation: 'to meet',
        lemmaTranslation: 'to get to know, to meet',
        morph: {'VerbForm': 'Inf'}),
  ]),
  _MockReply('Jak się dzisiaj czujesz?', [
    _MockWord('jak', 'ADV', translation: 'how', lemmaTranslation: 'how'),
    _MockWord('się', 'PRON', translation: 'yourself', lemmaTranslation: 'oneself'),
    _MockWord('dzisiaj', 'ADV', translation: 'today', lemmaTranslation: 'today'),
    _MockWord('czuć się', 'VERB',
        translation: 'do you feel',
        lemmaTranslation: 'to feel',
        morph: {'Person': '2', 'Number': 'Sing', 'Tense': 'Pres'}),
  ]),
  _MockReply('Lubię rozmawiać po polsku.', [
    _MockWord('lubić', 'VERB',
        translation: 'I like',
        lemmaTranslation: 'to like',
        morph: {'Person': '1', 'Number': 'Sing', 'Tense': 'Pres'}),
    _MockWord('rozmawiać', 'VERB',
        translation: 'to talk',
        lemmaTranslation: 'to talk, to converse',
        morph: {'VerbForm': 'Inf'}),
    _MockWord('po', 'ADP', translation: 'in', lemmaTranslation: 'in, along'),
    _MockWord('polsku', 'ADV', translation: 'Polish', lemmaTranslation: 'Polish'),
  ]),
  _MockReply('To jest bardzo dobre pytanie.', [
    _MockWord('to', 'PRON', translation: 'that', lemmaTranslation: 'that, this'),
    _MockWord('być', 'VERB',
        translation: 'is',
        lemmaTranslation: 'to be',
        morph: {'Person': '3', 'Number': 'Sing', 'Tense': 'Pres'}),
    _MockWord('bardzo', 'ADV', translation: 'very', lemmaTranslation: 'very'),
    _MockWord('dobry', 'ADJ',
        translation: 'good',
        lemmaTranslation: 'good',
        morph: {'Case': 'Nom', 'Gender': 'Neut'}),
    _MockWord('pytanie', 'NOUN',
        translation: 'question',
        lemmaTranslation: 'question',
        morph: {'Case': 'Nom', 'Gender': 'Neut'}),
  ]),
  _MockReply('Spróbujmy czegoś nowego razem.', [
    _MockWord('spróbować', 'VERB',
        translation: "let's try",
        lemmaTranslation: 'to try, to attempt',
        morph: {'Person': '1', 'Number': 'Plur', 'Mood': 'Imp'}),
    _MockWord('coś', 'PRON',
        translation: 'something', lemmaTranslation: 'something', morph: {'Case': 'Gen'}),
    _MockWord('nowy', 'ADJ',
        translation: 'new',
        lemmaTranslation: 'new',
        morph: {'Case': 'Gen', 'Gender': 'Neut'}),
    _MockWord('razem', 'ADV', translation: 'together', lemmaTranslation: 'together'),
  ]),
  _MockReply('Dziękuję za rozmowę!', [
    _MockWord('dziękować', 'VERB',
        translation: 'thank you',
        lemmaTranslation: 'to thank',
        morph: {'Person': '1', 'Number': 'Sing', 'Tense': 'Pres'}),
    _MockWord('za', 'ADP', translation: 'for', lemmaTranslation: 'for, behind'),
    _MockWord('rozmowa', 'NOUN',
        translation: 'the conversation',
        lemmaTranslation: 'conversation',
        morph: {'Case': 'Acc', 'Gender': 'Fem'}),
  ]),
];

List<TextToken> _mockTokensFor(_MockReply reply) {
  final words = reply.text.split(' ');
  var charPos = 0;
  final tokens = <TextToken>[];
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    final start = charPos;
    final end = start + w.length;
    final ann = reply.words[i % reply.words.length];
    tokens.add(TextToken(
      surface: w,
      lemma: ann.lemma,
      translation: ann.translation,
      lemmaTranslation: ann.lemmaTranslation,
      pos: ann.pos,
      morph: ann.morph,
      sentenceIndex: 0,
      charStart: start,
      charEnd: end,
    ));
    charPos = end + 1;
  }
  return tokens;
}

// ─── Screen (list of conversations <-> one open chat) ──────────────────────

enum _View { list, chat }

class ConverseScreen extends StatefulWidget {
  const ConverseScreen({super.key});

  @override
  State<ConverseScreen> createState() => _ConverseScreenState();
}

class _ConverseScreenState extends State<ConverseScreen> {
  _View _view = _View.list;
  List<Conversation> _conversations = [];
  Conversation? _active;
  Map<String, String>? _activeCourse;

  String? get _courseId {
    final c = _activeCourse;
    if (c == null) return null;
    return '${c['baseCode']}_${c['targetCode']}';
  }

  List<Conversation> get _courseConversations {
    final id = _courseId;
    if (id == null) return [];
    final list = _conversations.where((c) => c.courseId == id).toList();
    list.sort((a, b) {
      if (a.starred != b.starred) return a.starred ? -1 : 1;
      return b.lastActivity.compareTo(a.lastActivity);
    });
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
    AppStorage.instance.courseChanged.addListener(_onCourseChanged);
    AppStorage.instance.explainRequest.addListener(_onExplainRequested);
    // A request may already be pending if Read set it before this screen
    // was first built (it's created lazily inside HomeScreen's stack).
    _onExplainRequested();
  }

  @override
  void dispose() {
    AppStorage.instance.courseChanged.removeListener(_onCourseChanged);
    AppStorage.instance.explainRequest.removeListener(_onExplainRequested);
    super.dispose();
  }

  void _load() {
    _conversations = AppStorage.instance.conversations;
    _activeCourse = AppStorage.instance.activeCourse;
  }

  void _onCourseChanged() {
    if (!mounted) return;
    setState(() {
      _load();
      _view = _View.list;
      _active = null;
    });
  }

  void _persist() => AppStorage.instance.saveConversations(_conversations);

  void _openConversation(Conversation c) {
    setState(() {
      _active = c;
      _view = _View.chat;
    });
  }

  void _newConversation() {
    final id = _courseId;
    if (id == null) return;
    final c = Conversation(
        id: '${DateTime.now().millisecondsSinceEpoch}', courseId: id);
    setState(() {
      _conversations.insert(0, c);
      _active = c;
      _view = _View.chat;
    });
    _persist();
  }

  /// Opens a new conversation around a sentence handed off from the Read
  /// tab: the sentence itself as a word-tappable AI message, then a
  /// breakdown of its elements. The walkthrough text is assembled from the
  /// selection's token annotations — it stands in for a real AI explanation
  /// call the same way _mockReplies stand in for real chat replies.
  void _onExplainRequested() {
    final req = AppStorage.instance.explainRequest.value;
    if (req == null || !mounted) return;
    // Consume outside the notification pass so other listeners (the tab
    // switch in HomeScreen) still see the request.
    Future.microtask(() => AppStorage.instance.explainRequest.value = null);

    final now = DateTime.now().millisecondsSinceEpoch;
    final trimmed = req.text.trim();
    final short =
        trimmed.length > 34 ? '${trimmed.substring(0, 34)}…' : trimmed;
    final c = Conversation(
      id: '$now',
      courseId: req.courseId,
      title: 'Explain: $short',
      messages: [
        ChatMessage(
            id: '${now}_sentence',
            fromUser: false,
            text: trimmed,
            tokens: req.tokens),
        ChatMessage(
            id: '${now}_explain',
            fromUser: false,
            text: _explanationTextFor(req)),
      ],
    );
    setState(() {
      _conversations.insert(0, c);
      _active = c;
      _view = _View.chat;
    });
    _persist();
  }

  String _explanationTextFor(ExplainRequest req) {
    final b = StringBuffer();
    b.writeln("Let's take this sentence apart.");
    final translation = req.translation?.trim();
    if (translation != null && translation.isNotEmpty) {
      b.writeln();
      b.writeln('It means: "$translation"');
    }
    final words =
        req.tokens.where((t) => t.pos != 'PUNCT' && t.pos != 'NUM').toList();
    if (words.isNotEmpty) {
      b.writeln();
      b.writeln('Word by word:');
      for (final t in words) {
        final core = splitTrailingPunct(t.surface).core;
        if (core.isEmpty) continue;
        b.write('\n• $core — ${_posLabel(t.pos)}');
        if (t.morph.isNotEmpty) {
          final features = t.morph.entries
              .map((e) => morphLabel(e.key, e.value).toLowerCase())
              .join(', ');
          b.write(' ($features)');
        }
        final gloss = splitTrailingPunct(t.translation ?? '').core;
        if (gloss.isNotEmpty) b.write(' — "$gloss"');
        if (t.lemma != core.toLowerCase() && t.lemma != core) {
          b.write('. Base form: ${t.lemma}');
          final lemmaGloss = t.lemmaTranslation;
          if (lemmaGloss != null && lemmaGloss.isNotEmpty) {
            b.write(' ("$lemmaGloss")');
          }
        }
      }
      b.writeln();
    }
    b.writeln();
    b.write('Tap any word in the sentence above for details, '
        'or ask me anything about it!');
    return b.toString();
  }

  void _toggleStar(Conversation c) {
    setState(() => c.starred = !c.starred);
    _persist();
  }

  void _deleteConversation(Conversation c) {
    setState(() {
      _conversations.removeWhere((x) => x.id == c.id);
      if (_active?.id == c.id) {
        _active = null;
        _view = _View.list;
      }
    });
    _persist();
  }

  void _backToList() => setState(() {
        _view = _View.list;
        _active = null;
      });

  @override
  Widget build(BuildContext context) {
    return switch (_view) {
      _View.list => _ConversationListView(state: this),
      _View.chat => _ChatView(state: this, conversation: _active!),
    };
  }
}

// ─── List of conversations ──────────────────────────────────────────────────

class _ConversationListView extends StatelessWidget {
  final _ConverseScreenState state;
  const _ConversationListView({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasCourse = state._activeCourse != null;
    final conversations = state._courseConversations;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  Text('Converse',
                      style: GoogleFonts.cormorantGaramond(
                          color: AppColors.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w500)),
                  const Spacer(),
                  if (hasCourse)
                    Text(state._activeCourse?['targetFlag'] ?? '',
                        style: const TextStyle(fontSize: 20)),
                ],
              ),
            ),
            Expanded(
              child: !hasCourse
                  ? const _NoCourseState()
                  : conversations.isEmpty
                      ? _EmptyConversations(onStart: state._newConversation)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                          itemCount: conversations.length,
                          itemBuilder: (ctx, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _ConversationTile(
                              conversation: conversations[i],
                              onTap: () =>
                                  state._openConversation(conversations[i]),
                              onStar: () =>
                                  state._toggleStar(conversations[i]),
                              onDelete: () =>
                                  state._deleteConversation(conversations[i]),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: hasCourse
          ? FloatingActionButton(
              heroTag: 'converse_fab',
              onPressed: state._newConversation,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              child: const Icon(Icons.add_comment_rounded),
            )
          : null,
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback onStar;
  final VoidCallback onDelete;
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
    required this.onStar,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final lastMsg =
        conversation.messages.isEmpty ? null : conversation.messages.last;
    return Dismissible(
      key: Key(conversation.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF3A1A1A),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFE57373)),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: conversation.starred
                    ? AppColors.primary
                    : AppColors.border,
                width: conversation.starred ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conversation.displayTitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.dmSans(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    if (lastMsg != null) ...[
                      const SizedBox(height: 3),
                      Text(lastMsg.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                              color: AppColors.text2, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              GestureDetector(
                onTap: onStar,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    conversation.starred
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: conversation.starred
                        ? const Color(0xFFFFB74D)
                        : AppColors.text3,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoCourseState extends StatelessWidget {
  const _NoCourseState();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined,
                  size: 56, color: AppColors.text3),
              const SizedBox(height: 20),
              Text('Select a course',
                  style: GoogleFonts.cormorantGaramond(
                      color: AppColors.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w400)),
              const SizedBox(height: 10),
              Text(
                'Pick a course in Read or Flashcards to start a conversation.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                    color: AppColors.text2, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      );
}

class _EmptyConversations extends StatelessWidget {
  final VoidCallback onStart;
  const _EmptyConversations({required this.onStart});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined,
                  size: 56, color: AppColors.text3),
              const SizedBox(height: 20),
              Text('No conversations yet',
                  style: GoogleFonts.cormorantGaramond(
                      color: AppColors.text,
                      fontSize: 26,
                      fontWeight: FontWeight.w400)),
              const SizedBox(height: 10),
              Text('Start chatting to practice in a real conversation.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                      color: AppColors.text2, fontSize: 14, height: 1.5)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onStart,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
                child: Text('New conversation',
                    style: GoogleFonts.dmSans(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
}

// ─── Chat view ───────────────────────────────────────────────────────────────

class _ChatView extends StatefulWidget {
  final _ConverseScreenState state;
  final Conversation conversation;
  const _ChatView({required this.state, required this.conversation});

  @override
  State<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<_ChatView> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final FlutterTts _tts = FlutterTts();
  int _replyCursor = 0;
  bool _sending = false;
  // Identifies one tapped token instance (message id + its char offset) so
  // only that exact word highlights — same affordance as Read's word tap.
  String? _tappedKey;
  // Inspect mode (same interaction as Read): the tapped word stays
  // highlighted and a docked bar below the chat steps through the words of
  // that message and opens the word sheet on demand.
  String? _inspectMsgId;
  int? _inspectStart;

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String text, String langCode) async {
    await _tts.setLanguage(_ttsLocaleFor(langCode));
    await _tts.setSpeechRate(0.45);
    await _tts.speak(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    final userMsg = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        fromUser: true,
        text: text);
    setState(() {
      widget.conversation.messages.add(userMsg);
      _sending = true;
    });
    widget.state._persist();
    _scrollToBottom();

    // Real AI reply through the backend; the canned replies remain as an
    // offline/no-session fallback.
    ChatMessage aiMsg;
    final course = widget.state._activeCourse;
    Map<String, dynamic>? res;
    if (ApiClient.instance.hasSession && course != null) {
      try {
        res = await ApiClient.instance.chatReply(
          targetLang: course['targetCode'] ?? '',
          baseLang: course['baseCode'] ?? '',
          messages: [
            for (final m in widget.conversation.messages.length > 20
                ? widget.conversation.messages
                    .sublist(widget.conversation.messages.length - 20)
                : widget.conversation.messages)
              {'fromUser': m.fromUser, 'text': m.text},
          ],
        );
      } on ApiException {
        res = null;
      }
    }
    if (res != null) {
      aiMsg = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_ai',
        fromUser: false,
        text: res['text'] as String,
        tokens: [
          for (final t in res['tokens'] as List)
            TextToken.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
      );
    } else {
      await Future.delayed(const Duration(milliseconds: 700));
      final reply = _mockReplies[_replyCursor % _mockReplies.length];
      _replyCursor++;
      aiMsg = ChatMessage(
        id: '${DateTime.now().millisecondsSinceEpoch}_ai',
        fromUser: false,
        text: reply.text,
        tokens: _mockTokensFor(reply),
      );
    }
    if (!mounted) return;
    setState(() {
      widget.conversation.messages.add(aiMsg);
      _sending = false;
    });
    widget.state._persist();
    _scrollToBottom();
  }

  void _onWordTap(String messageId, TextToken token) {
    setState(() {
      final key = '$messageId:${token.charStart}';
      if (_tappedKey == key) {
        _clearInspection();
      } else {
        _inspectMsgId = messageId;
        _inspectStart = token.charStart;
        _tappedKey = key;
      }
    });
  }

  void _clearInspection() {
    _inspectMsgId = null;
    _inspectStart = null;
    _tappedKey = null;
  }

  ChatMessage? _inspectMessage() {
    if (_inspectMsgId == null) return null;
    for (final m in widget.conversation.messages) {
      if (m.id == _inspectMsgId) return m;
    }
    return null;
  }

  List<TextToken> _navigableTokens(ChatMessage message) => [
        for (final t in message.tokens)
          if (!_isPunctSurface(t.surface) && t.translation != null) t,
      ];

  TextToken? _inspectedToken() {
    final message = _inspectMessage();
    if (message == null || _inspectStart == null) return null;
    for (final t in message.tokens) {
      if (t.charStart == _inspectStart) return t;
    }
    return null;
  }

  void _inspectStep(int direction) {
    final message = _inspectMessage();
    if (message == null) return;
    final tokens = _navigableTokens(message);
    if (tokens.isEmpty) return;
    final current = tokens.indexWhere((t) => t.charStart == _inspectStart);
    final next = (current + direction).clamp(0, tokens.length - 1);
    setState(() {
      _inspectStart = tokens[next].charStart;
      _tappedKey = '${message.id}:${tokens[next].charStart}';
    });
  }

  void _showWordSheet(TextToken token) {
    final targetCode = widget.state._activeCourse?['targetCode'] ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ChatWordSheet(
        token: token,
        onSpeakSurface: () =>
            _speak(splitTrailingPunct(token.surface).core, targetCode),
        onSpeakLemma: () => _speak(token.lemma, targetCode),
        onAddToFlashcards: () => _addToFlashcards(token),
      ),
    );
  }

  Widget _inspectBarButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon,
            size: 24,
            color: onTap == null ? AppColors.text3 : AppColors.text),
      ),
    );
  }

  /// Same docked inspect bar as the reader: arrows step through the words
  /// of the inspected message, the middle shows the gloss inline, and the
  /// book button (or tapping the gloss) opens the word sheet.
  Widget _buildInspectBar(TextToken token) {
    final gloss = splitTrailingPunct((token.translation ?? '').trim()).core;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _inspectBarButton(
              Icons.chevron_left_rounded, () => _inspectStep(-1)),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _showWordSheet(token),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    splitTrailingPunct(token.surface).core,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    gloss.isEmpty ? '—' : gloss,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                        color: AppColors.primarySoft, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _inspectBarButton(
              Icons.menu_book_rounded, () => _showWordSheet(token)),
          const SizedBox(width: 10),
          _inspectBarButton(
              Icons.chevron_right_rounded, () => _inspectStep(1)),
        ],
      ),
    );
  }

  void _addToFlashcards(TextToken token) {
    final courseId = widget.state._courseId;
    Navigator.pop(context);
    if (courseId == null) return;
    final storage = AppStorage.instance;
    final existing = storage.flashcards;
    final already =
        existing.any((c) => c.courseId == courseId && c.word == token.lemma);
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(
          _snack('"${token.lemma}" is already in your flashcards'));
      return;
    }
    final card = Flashcard(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      word: token.lemma,
      translation: token.lemmaTranslation ?? token.translation ?? '',
      wordType: _posLabel(token.pos),
      courseId: courseId,
      morph: (token.pos == 'NOUN' || token.pos == 'PROPN') &&
              token.morph.containsKey('Gender')
          ? {'Gender': token.morph['Gender']!}
          : null,
    );
    storage.saveFlashcards([...existing, card]);
    storage.flashcardsChanged.value++;
    ScaffoldMessenger.of(context)
        .showSnackBar(_snack('"${token.lemma}" added to flashcards'));
  }

  SnackBar _snack(String message) => SnackBar(
        content: Text(message,
            style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 13)),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      );

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    final targetCode = widget.state._activeCourse?['targetCode'] ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: widget.state._backToList,
        ),
        title: Text(conversation.displayTitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: conversation.messages.isEmpty
                  ? Center(
                      child: Text('Say hello to start practicing.',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3, fontSize: 14)))
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      itemCount: conversation.messages.length,
                      itemBuilder: (ctx, i) => _MessageBubble(
                        message: conversation.messages[i],
                        tappedKey: _tappedKey,
                        onWordTap: (token) =>
                            _onWordTap(conversation.messages[i].id, token),
                        onSpeak: () =>
                            _speak(conversation.messages[i].text, targetCode),
                      ),
                    ),
            ),
            if (_sending)
              Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.text3)),
                    const SizedBox(width: 8),
                    Text('typing…',
                        style: GoogleFonts.dmSans(
                            color: AppColors.text3, fontSize: 12)),
                  ],
                ),
              ),
            Builder(builder: (_) {
              final inspected = _inspectedToken();
              return inspected == null
                  ? const SizedBox.shrink()
                  : _buildInspectBar(inspected);
            }),
            _ChatInputBar(controller: _ctrl, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final String? tappedKey;
  final void Function(TextToken) onWordTap;
  final VoidCallback onSpeak;
  const _MessageBubble(
      {required this.message,
      this.tappedKey,
      required this.onWordTap,
      required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isUser)
              Text(message.text,
                  style: GoogleFonts.dmSans(
                      color: Colors.white, fontSize: 15, height: 1.4))
            else
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: message.tokens.isEmpty
                    ? [
                        Text(message.text,
                            style: GoogleFonts.dmSans(
                                color: AppColors.text,
                                fontSize: 15,
                                height: 1.4))
                      ]
                    : _groupTokens(message.tokens).map((g) {
                        final t = g.token;
                        final isTapped =
                            tappedKey == '${message.id}:${t.charStart}';
                        final base = splitTrailingPunct(t.surface);
                        final split = (core: base.core, trail: base.trail + g.trail);
                        return GestureDetector(
                          onTap: () => onWordTap(t),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 80),
                                padding: EdgeInsets.only(
                                    left: 2,
                                    right: split.trail.isEmpty ? 2 : 0,
                                    top: 1,
                                    bottom: 1),
                                decoration: BoxDecoration(
                                  color: isTapped
                                      ? AppColors.primaryGlow
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(split.core,
                                    style: GoogleFonts.dmSans(
                                        color: isTapped
                                            ? AppColors.primarySoft
                                            : AppColors.text,
                                        fontSize: 15,
                                        height: 1.4,
                                        decoration: TextDecoration.underline,
                                        decorationColor: AppColors.primary
                                            .withValues(alpha: 0.4),
                                        decorationStyle:
                                            TextDecorationStyle.dotted)),
                              ),
                              if (split.trail.isNotEmpty)
                                Text(split.trail,
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.text,
                                        fontSize: 15,
                                        height: 1.4)),
                            ],
                          ),
                        );
                      }).toList(),
              ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isUser) ...[
                  GestureDetector(
                    onTap: onSpeak,
                    child: Icon(Icons.volume_up_rounded,
                        size: 15, color: AppColors.text3),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(_fmtTime(message.createdAt),
                    style: GoogleFonts.dmSans(
                        color: isUser ? Colors.white70 : AppColors.text3,
                        fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _ChatInputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                filled: true,
                fillColor: AppColors.card,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: const BorderSide(color: AppColors.primary)),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Word sheet (tap a word in an AI message) ──────────────────────────────
// Mirrors read_screen.dart's _WordSheet — same sections (word, attributes,
// translation, base form, root), minus the deck picker (single tap adds to
// General, matching the simpler "wstępna wersja" scope). Shares
// morphLabel/AttributeChip via widgets/word_attributes.dart.

class _ChatWordSheet extends StatelessWidget {
  final TextToken token;
  final VoidCallback? onSpeakSurface;
  final VoidCallback? onSpeakLemma;
  final VoidCallback onAddToFlashcards;
  const _ChatWordSheet({
    required this.token,
    this.onSpeakSurface,
    this.onSpeakLemma,
    required this.onAddToFlashcards,
  });

  Widget _sectionLabel(String text) => Text(text,
      style: GoogleFonts.dmSans(
          color: AppColors.text3,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2));

  Widget _infoBox({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final displayWord = splitTrailingPunct(token.surface).core;
    final displayTranslation = splitTrailingPunct(token.translation ?? '').core;
    final hasBaseForm = token.lemma != displayWord;
    final hasRoot = token.root != null && token.root!.isNotEmpty;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(displayWord,
                              style: GoogleFonts.cormorantGaramond(
                                  color: AppColors.text,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w400,
                                  height: 1.0)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onSpeakSurface,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Icon(Icons.volume_up_rounded,
                                color: AppColors.text2, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(_posLabel(token.pos),
                        style: GoogleFonts.dmSans(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5)),
                    if (token.morph.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: token.morph.entries
                            .map((e) => AttributeChip(
                                label: morphLabel(e.key, e.value)))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _sectionLabel('TRANSLATION'),
                    const SizedBox(height: 8),
                    _infoBox(
                      child: Text(displayTranslation,
                          style: GoogleFonts.dmSans(
                              color: AppColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (hasBaseForm) ...[
                      const SizedBox(height: 18),
                      _sectionLabel('BASE FORM'),
                      const SizedBox(height: 8),
                      _infoBox(
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(token.lemma,
                                      style: GoogleFonts.dmSans(
                                          color: AppColors.text,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                      token.lemmaTranslation ??
                                          token.translation ??
                                          '',
                                      style: GoogleFonts.dmSans(
                                          color: AppColors.text2,
                                          fontSize: 14)),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: onSpeakLemma,
                              child: Icon(Icons.volume_up_rounded,
                                  color: AppColors.text3, size: 18),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (hasRoot) ...[
                      const SizedBox(height: 18),
                      _sectionLabel('ROOT'),
                      const SizedBox(height: 8),
                      _infoBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(token.root!,
                                style: GoogleFonts.dmSans(
                                    color: AppColors.primarySoft,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            if (token.rootMeaning != null) ...[
                              const SizedBox(height: 4),
                              Text(token.rootMeaning!,
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text2,
                                      fontSize: 13,
                                      height: 1.4)),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: onAddToFlashcards,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add_rounded,
                                color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text('Add to flashcards',
                                style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
