import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/app_storage.dart';
import '../services/language_levels.dart';
import '../models/flashcard.dart';
import '../models/deck.dart';
import '../data/alphabet_data.dart';
import '../widgets/course_badge.dart';
import '../widgets/level_up_overlay.dart';
import '../widgets/word_attributes.dart';
import 'language_screen.dart';

// ─── View enum ───────────────────────────────────────────────────────────────

enum _View { hub, deck, cardList, addCard, learn, write, quiz, match, babelReview, babelLearn }

// ─── Activity descriptor ─────────────────────────────────────────────────────

class _Activity {
  final String key;
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  const _Activity({
    required this.key,
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
  });
}

// ─── Babel group (same base word across multiple target languages) ────────────

class _BabelGroup {
  final String baseWord;
  final Map<String, Flashcard> byCourseId;
  // true  → cards connected by word field; per-language display = translation
  // false → cards connected by translation field; per-language display = word
  final bool groupedByWord;

  const _BabelGroup({
    required this.baseWord,
    required this.byCourseId,
    required this.groupedByWord,
  });

  String displayFor(Flashcard card) =>
      groupedByWord ? card.translation : card.word;
}

// ─── Flashcard settings ───────────────────────────────────────────────────────

class FlashcardsSettings {
  bool reversedReview;
  bool reversedWrite;
  bool reversedQuiz;
  bool reversedMatch;
  int writeQuestions;
  int quizQuestions;
  int quizOptions;
  int matchRounds;
  int matchPairs;
  Set<String> hiddenTargetCodes;

  FlashcardsSettings({
    this.reversedReview = false,
    this.reversedWrite = true,
    this.reversedQuiz = true,
    this.reversedMatch = true,
    this.writeQuestions = 20,
    this.quizQuestions = 20,
    this.quizOptions = 4,
    this.matchRounds = 3,
    this.matchPairs = 6,
    Set<String>? hiddenTargetCodes,
  }) : hiddenTargetCodes = hiddenTargetCodes ?? {};

  Map<String, dynamic> toJson() => {
        'reversedReview': reversedReview,
        'reversedWrite': reversedWrite,
        'reversedQuiz': reversedQuiz,
        'reversedMatch': reversedMatch,
        'writeQuestions': writeQuestions,
        'quizQuestions': quizQuestions,
        'quizOptions': quizOptions,
        'matchRounds': matchRounds,
        'matchPairs': matchPairs,
        'hiddenTargetCodes': hiddenTargetCodes.toList(),
      };

  factory FlashcardsSettings.fromJson(Map<String, dynamic> j) =>
      FlashcardsSettings(
        reversedReview: j['reversedReview'] as bool? ?? false,
        reversedWrite: j['reversedWrite'] as bool? ?? true,
        reversedQuiz: j['reversedQuiz'] as bool? ?? true,
        reversedMatch: j['reversedMatch'] as bool? ?? true,
        writeQuestions: j['writeQuestions'] as int? ?? 20,
        quizQuestions: j['quizQuestions'] as int? ?? 20,
        quizOptions: j['quizOptions'] as int? ?? 4,
        matchRounds: j['matchRounds'] as int? ?? 3,
        matchPairs: j['matchPairs'] as int? ?? 6,
        hiddenTargetCodes: Set<String>.from(
            j['hiddenTargetCodes'] as List? ?? []),
      );
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _ttsLocaleFor(String code) =>
    alphabetFor(code)?.ttsLocale ?? '$code-${code.toUpperCase()}';

const _activities = [
  _Activity(
    key: 'review',
    label: 'Review',
    sublabel: 'Browse all cards',
    icon: Icons.view_list_rounded,
    color: Color(0xFF7C5CFC),
  ),
  _Activity(
    key: 'learn',
    label: 'Learn',
    sublabel: 'Gallery mode',
    icon: Icons.auto_awesome_rounded,
    color: Color(0xFFFFB74D),
  ),
  _Activity(
    key: 'write',
    label: 'Write',
    sublabel: 'Type the answer',
    icon: Icons.edit_rounded,
    color: Color(0xFF4CACF0),
  ),
  _Activity(
    key: 'quiz',
    label: 'Quiz',
    sublabel: '4-choice test',
    icon: Icons.quiz_rounded,
    color: Color(0xFFE040FB),
  ),
  _Activity(
    key: 'match',
    label: 'Match',
    sublabel: 'Pair them up',
    icon: Icons.compare_arrows_rounded,
    color: Color(0xFF26C6DA),
  ),
];

// ─── Root screen ─────────────────────────────────────────────────────────────

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  _View _view = _View.hub;

  List<Flashcard> _cards = [];
  List<Deck> _decks = [];
  Deck? _selectedDeck;
  final Set<String> _activeTypeFilters = {};

  static const _untypedKey = '__untyped__';

  Map<String, String>? _activeCourse;
  List<Map<String, String>> _pickerBases = [];
  List<Map<String, String>> _pickerCourses = [];
  String? _pickerSelectedBase;
  Map<String, FlashcardsSettings> _deckSettings = {};

  FlashcardsSettings _settingsFor(String deckId) =>
      _deckSettings.putIfAbsent(deckId, FlashcardsSettings.new);

  // ── Derived ─────────────────────────────────────────────────────────────────

  String? get _courseId {
    final c = _activeCourse;
    if (c == null) return null;
    return '${c['baseCode']}_${c['targetCode']}';
  }

  List<Flashcard> get _courseCards {
    final id = _courseId;
    if (id == null) return [];
    return _cards
        .where((c) => c.courseId == id && !c.id.startsWith('alphabet_'))
        .toList();
  }

  List<Deck> get _courseDecks {
    final id = _courseId;
    if (id == null) return [];
    final stored = _decks.where((d) => d.courseId == id && !d.isVirtual).toList();
    final target = _activeCourse?['targetCode'] ?? '';
    final alphabet = alphabetFor(target);
    final alphabetDecks = alphabet != null
        ? [Deck.alphabet(id, alphabet.nativeName)]
        : <Deck>[];
    // Babel is always shown, even with no cross-language groups yet.
    final babelDecks = [Deck.babel(id)];
    return [...babelDecks, ...alphabetDecks, Deck.general(id), Deck.fromTexts(id), ...stored];
  }

  List<Flashcard> _alphabetCards() {
    final id = _courseId;
    if (id == null) return [];
    final target = _activeCourse?['targetCode'] ?? '';
    final alphabet = alphabetFor(target);
    if (alphabet == null) return [];
    return alphabet.groups
        .expand((g) => g.entries)
        .map((e) {
          final cardId = 'alphabet_${id}_${e.char}';
          return _cards.firstWhere(
            (c) => c.id == cardId,
            orElse: () => Flashcard(
              id: cardId,
              word: e.char,
              translation: e.phoneticFor('latin'),
              courseId: id,
            ),
          );
        })
        .toList();
  }

  List<_BabelGroup> _babelGroups() {
    final baseCode = _activeCourse?['baseCode'];
    if (baseCode == null) return [];
    final hidden = _settingsFor(Deck.babelId).hiddenTargetCodes;
    final sameCourseIds = _pickerCourses
        .where((c) =>
            c['baseCode'] == baseCode &&
            !hidden.contains(c['targetCode']))
        .map((c) => '${c['baseCode']}_${c['targetCode']}')
        .toSet();
    if (sameCourseIds.length < 2) return [];
    final allCards = _cards
        .where((c) =>
            sameCourseIds.contains(c.courseId) && !c.id.startsWith('alphabet_'))
        .toList();

    // Build a group map keyed by a normalised text value.
    Map<String, Map<String, Flashcard>> buildIndex(
        String Function(Flashcard) keyOf) {
      final map = <String, Map<String, Flashcard>>{};
      for (final card in allCards) {
        map
            .putIfAbsent(keyOf(card).trim().toLowerCase(), () => {})
            .putIfAbsent(card.courseId, () => card);
      }
      return map;
    }

    final byWord = buildIndex((c) => c.word);
    final byTranslation = buildIndex((c) => c.translation);

    // Track which card-ID sets we've already added to avoid duplicates
    final seenCardSets = <String>{};
    final result = <_BabelGroup>[];

    void harvest(Map<String, Map<String, Flashcard>> index, bool byWordFlag) {
      for (final entry in index.entries) {
        if (entry.value.length < 2) continue;
        final setKey =
            (entry.value.values.map((c) => c.id).toList()..sort()).join(',');
        if (!seenCardSets.add(setKey)) continue;
        final first = entry.value.values.first;
        result.add(_BabelGroup(
          baseWord: byWordFlag ? first.word : first.translation,
          byCourseId: entry.value,
          groupedByWord: byWordFlag,
        ));
      }
    }

    harvest(byWord, true);
    harvest(byTranslation, false);

    result.sort((a, b) => a.baseWord.compareTo(b.baseWord));
    return result;
  }

  List<Flashcard> _babelCards() {
    final seen = <String>{};
    final result = <Flashcard>[];
    for (final g in _babelGroups()) {
      for (final card in g.byCourseId.values) {
        if (seen.add(card.id)) result.add(card);
      }
    }
    return result;
  }

  List<Flashcard> cardsForDeck(String deckId) {
    if (deckId == Deck.generalId) return _courseCards;
    if (deckId == Deck.fromTextsId) return _courseCards.where((c) => c.fromTexts).toList();
    if (deckId == Deck.alphabetId) return _alphabetCards();
    if (deckId == Deck.babelId) return _babelCards();
    return _courseCards.where((c) => c.deckIds.contains(deckId)).toList();
  }

  int dueForDeck(String deckId) =>
      cardsForDeck(deckId).where((c) => c.isDue).length;

  List<Flashcard> get _rawDeckCards {
    final d = _selectedDeck;
    if (d == null) return _courseCards;
    return cardsForDeck(d.id);
  }

  List<Flashcard> get _deckCards {
    if (_activeTypeFilters.isEmpty) return _rawDeckCards;
    return _rawDeckCards.where((c) {
      final key = c.wordType ?? _untypedKey;
      return _activeTypeFilters.contains(key);
    }).toList();
  }

  Set<String> get _deckAvailableTypes {
    final types = <String>{};
    for (final c in _rawDeckCards) {
      types.add(c.wordType ?? _untypedKey);
    }
    return types;
  }

  List<Flashcard> get _deckDueCards => _deckCards.where((c) => c.isDue).toList();

  void _toggleTypeFilter(String key) {
    setState(() {
      if (_activeTypeFilters.contains(key)) {
        _activeTypeFilters.remove(key);
      } else {
        _activeTypeFilters.add(key);
      }
    });
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
    AppStorage.instance.flashcardsChanged.addListener(_onExternalCardsChanged);
    // Course selection is global — reload when another tab (e.g. Read)
    // changes it, since IndexedStack keeps this screen's state alive.
    AppStorage.instance.courseChanged.addListener(_reloadActiveCourse);
  }

  @override
  void dispose() {
    AppStorage.instance.flashcardsChanged.removeListener(_onExternalCardsChanged);
    AppStorage.instance.courseChanged.removeListener(_reloadActiveCourse);
    super.dispose();
  }

  void _onExternalCardsChanged() {
    if (mounted) setState(_loadFromStorage);
  }

  void _reloadActiveCourse() {
    if (!mounted) return;
    setState(() {
      _pickerBases = AppStorage.instance.bases;
      _pickerCourses = AppStorage.instance.courses;
      _pickerSelectedBase = AppStorage.instance.selectedBase;
      final newCourse = AppStorage.instance.activeCourse;
      final changed = newCourse?['baseCode'] != _activeCourse?['baseCode'] ||
          newCourse?['targetCode'] != _activeCourse?['targetCode'];
      _activeCourse = newCourse;
      if (changed && _view != _View.hub) {
        _view = _View.hub;
        _selectedDeck = null;
        AppStorage.instance.hideAlphabetPanel.value = false;
      }
    });
  }

  void _loadFromStorage() {
    _cards = AppStorage.instance.flashcards;
    _decks = AppStorage.instance.decks;
    _pickerBases = AppStorage.instance.bases;
    _pickerCourses = AppStorage.instance.courses;
    _pickerSelectedBase = AppStorage.instance.selectedBase;
    _activeCourse = AppStorage.instance.activeCourse;
    final raw = AppStorage.instance.deckSettings;
    _deckSettings = raw.map((k, v) => MapEntry(
        k, FlashcardsSettings.fromJson(Map<String, dynamic>.from(v as Map))));
    _snapshotLanguageLevels();
  }

  /// Last known level per target language — the baseline the next grade is
  /// compared against, so a level-up celebration fires exactly when a
  /// practice answer pushes a language over a threshold. Rebuilt on every
  /// (re)load so changes made outside practicing never trigger it.
  Map<String, int> _languageLevelSnapshot = {};

  void _snapshotLanguageLevels() {
    _languageLevelSnapshot = {
      for (final l
          in computeLanguageLevels(cards: _cards, courses: _pickerCourses))
        l.targetCode: l.level,
    };
  }

  void _celebrateLevelUps() {
    for (final lang
        in computeLanguageLevels(cards: _cards, courses: _pickerCourses)) {
      final before = _languageLevelSnapshot[lang.targetCode] ?? 0;
      _languageLevelSnapshot[lang.targetCode] = lang.level;
      if (lang.level > before && mounted) {
        showLevelUpCelebration(
          context,
          languageName: lang.targetName,
          languageFlag: lang.targetFlag,
          level: lang.level,
        );
      }
    }
  }

  void _saveCards() => AppStorage.instance.saveFlashcards(_cards);
  void _saveDecks() =>
      AppStorage.instance.saveDecks(_decks.where((d) => !d.isVirtual).toList());
  void _saveDeckSettings() =>
      AppStorage.instance.saveDeckSettings(
          _deckSettings.map((k, v) => MapEntry(k, v.toJson())));

  void _showSettingsSheet(BuildContext context, String deckId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SettingsSheet(state: this, deckId: deckId),
    );
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────────

  void _addCard(Flashcard card) {
    setState(() => _cards.insert(0, card));
    _saveCards();
  }

  void _updateCard(Flashcard card) {
    setState(() {
      final i = _cards.indexWhere((c) => c.id == card.id);
      if (i != -1) {
        _cards[i] = card;
      } else {
        _cards.add(card);
      }
    });
    _saveCards();
    _celebrateLevelUps();
  }

  /// Clears the "NEW" badge for cards once they've been shown in Review or
  /// practiced elsewhere — a no-op setState for cards already seen.
  void _markSeen(Iterable<Flashcard> cards) {
    var changed = false;
    for (final c in cards) {
      if (!c.seen) {
        c.seen = true;
        changed = true;
      }
    }
    if (changed) _saveCards();
  }

  void _deleteCard(Flashcard card) {
    setState(() => _cards.removeWhere((c) => c.id == card.id));
    _saveCards();
  }

  Deck? _addDeck(String name, {String type = Deck.typeVocab}) {
    final id = _courseId;
    if (id == null) return null;
    final deck = Deck(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        courseId: id,
        type: type);
    setState(() => _decks.add(deck));
    _saveDecks();
    return deck;
  }

  void _deleteDeck(Deck deck) {
    if (deck.isVirtual) return;
    setState(() {
      for (final c in _cards) {
        c.deckIds.remove(deck.id);
      }
      _decks.removeWhere((d) => d.id == deck.id);
    });
    _saveCards();
    _saveDecks();
  }

  // ── Navigation ────────────────────────────────────────────────────────────────

  void _goHome() => setState(() {
        _view = _View.hub;
        _selectedDeck = null;
        AppStorage.instance.hideAlphabetPanel.value = false;
      });

  void _openDeck(Deck deck) => setState(() {
        _selectedDeck = deck;
        _activeTypeFilters.clear();
        _view = _View.deck;
        AppStorage.instance.hideAlphabetPanel.value = deck.isBabel;
      });

  void _goToDeckHub() => setState(() => _view = _View.deck);

  void _goToCardList() => setState(() => _view = _View.cardList);

  void _goToAddCard() => setState(() => _view = _View.addCard);

  void _openActivity(String key) => setState(() {
        final babel = _selectedDeck?.isBabel == true;
        _view = switch (key) {
          'review' => babel ? _View.babelReview : _View.cardList,
          'learn'  => babel ? _View.babelLearn  : _View.learn,
          'write'  => _View.write,
          'quiz'   => _View.quiz,
          _        => _View.match,
        };
      });

  // ── Language sheet ───────────────────────────────────────────────────────────

  void _showBabelBaseSheet(BuildContext context) {
    final uniqueBases = <String, Map<String, String>>{};
    for (final c in _pickerCourses) {
      final code = c['baseCode'] ?? '';
      if (code.isNotEmpty) uniqueBases.putIfAbsent(code, () => c);
    }
    final activeBase = _activeCourse?['baseCode'];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 20, 24, MediaQuery.of(ctx).padding.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Base language',
                style: GoogleFonts.cormorantGaramond(
                    color: AppColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            ...uniqueBases.values.map((c) {
              final active = c['baseCode'] == activeBase;
              return GestureDetector(
                onTap: () {
                  final newCourse = _pickerCourses.firstWhere(
                    (p) => p['baseCode'] == c['baseCode'],
                    orElse: () => c,
                  );
                  setState(() => _activeCourse = newCourse);
                  Navigator.pop(ctx);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Text(c['baseFlag'] ?? '',
                          style: const TextStyle(fontSize: 22, height: 1.2)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(c['baseName'] ?? '',
                            style: GoogleFonts.dmSans(
                                color: AppColors.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                      ),
                      if (active)
                        const Icon(Icons.check_rounded,
                            size: 18, color: AppColors.primary),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showLanguageSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('My courses',
                      style: GoogleFonts.cormorantGaramond(
                          color: AppColors.text,
                          fontSize: 28,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: LanguagePickerContent(
                  initialBases: _pickerBases,
                  initialCourses: _pickerCourses,
                  initialSelectedBase: _pickerSelectedBase,
                  initialActiveCourse: _activeCourse,
                  onCoursesChanged: (_) {},
                  onCourseTapped: (course) {
                    setState(() => _activeCourse = course);
                    Navigator.pop(context);
                  },
                  onStateChanged: (bases, courses, selectedBase, activeCourse) {
                    setState(() {
                      _pickerBases = List.from(bases);
                      _pickerCourses = List.from(courses);
                      _pickerSelectedBase = selectedBase;
                      if (activeCourse != null) _activeCourse = activeCourse;
                    });
                    AppStorage.instance.saveCourseState(
                      bases: bases,
                      courses: courses,
                      selectedBase: selectedBase,
                      activeCourse: activeCourse,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── New deck dialog ──────────────────────────────────────────────────────────

  void _showNewDeckDialog() {
    final ctrl = TextEditingController();
    var type = Deck.typeVocab;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: AppColors.card,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('New deck',
              style: GoogleFonts.cormorantGaramond(
                  color: AppColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w500)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
                decoration: const InputDecoration(hintText: 'Deck name'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DeckTypeChip(
                    label: 'Vocabulary',
                    icon: Icons.style_rounded,
                    selected: type == Deck.typeVocab,
                    onTap: () => setDialog(() => type = Deck.typeVocab),
                  ),
                  _DeckTypeChip(
                    label: 'Phrases',
                    icon: Icons.format_quote_rounded,
                    selected: type == Deck.typePhrases,
                    onTap: () => setDialog(() => type = Deck.typePhrases),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.dmSans(color: AppColors.text2)),
            ),
            // Create the deck and immediately open AI generation for it.
            TextButton(
              onPressed: () {
                if (ctrl.text.trim().isEmpty) return;
                final deck = _addDeck(ctrl.text.trim(), type: type);
                Navigator.pop(ctx);
                if (deck != null) _showDeckGenerationSheet(context, deck);
              },
              child: Text('Create & generate',
                  style: GoogleFonts.dmSans(
                      color: AppColors.primarySoft,
                      fontWeight: FontWeight.w600)),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  _addDeck(ctrl.text.trim(), type: type);
                  Navigator.pop(ctx);
                }
              },
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('Create',
                  style: GoogleFonts.dmSans(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI deck generation ───────────────────────────────────────────────────────

  static const _genCounts = [5, 10, 15, 20, 30, 50];
  static const _genLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  /// Bottom sheet for filling a user deck with AI-generated content:
  /// topic (typed), count and level. Vocabulary decks get single words,
  /// phrase decks get expressions.
  void _showDeckGenerationSheet(BuildContext context, Deck deck) {
    final course = _activeCourse;
    if (course == null) return;
    if (!ApiClient.instance.hasSession) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sign in to generate decks with AI',
            style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 13)),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final topicCtrl = TextEditingController();
    var count = 10;
    var level = 'B1';
    var generating = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                      deck.isPhrases
                          ? Icons.format_quote_rounded
                          : Icons.style_rounded,
                      size: 20,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                        deck.isPhrases
                            ? 'Generate phrases'
                            : 'Generate vocabulary',
                        style: GoogleFonts.cormorantGaramond(
                            color: AppColors.text,
                            fontSize: 24,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: topicCtrl,
                autofocus: true,
                style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
                decoration: const InputDecoration(
                    hintText: 'Topic, e.g. kitchen, fruit, travel…'),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 18),
              Text('HOW MANY',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _genCounts)
                    _SheetChip(
                        label: '$c',
                        selected: count == c,
                        onTap: () => setSheet(() => count = c)),
                ],
              ),
              const SizedBox(height: 16),
              Text('LEVEL',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in _genLevels)
                    _SheetChip(
                        label: l,
                        selected: level == l,
                        onTap: () => setSheet(() => level = l)),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: generating
                      ? null
                      : () async {
                          final topic = topicCtrl.text.trim();
                          if (topic.isEmpty) return;
                          setSheet(() => generating = true);
                          try {
                            final items =
                                await ApiClient.instance.generateDeck(
                              targetLang: course['targetCode'] ?? '',
                              baseLang: course['baseCode'] ?? '',
                              topic: topic,
                              count: count,
                              level: level,
                              kind: deck.isPhrases
                                  ? Deck.typePhrases
                                  : Deck.typeVocab,
                            );
                            if (!ctx.mounted) return;
                            final added = _addGeneratedCards(deck, items);
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(
                              content: Text(
                                  added == items.length
                                      ? 'Added $added cards to "${deck.name}"'
                                      : 'Added $added cards ('
                                          '${items.length - added} already '
                                          'existed)',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text, fontSize: 13)),
                              backgroundColor: AppColors.card,
                              behavior: SnackBarBehavior.floating,
                            ));
                          } on ApiException catch (e) {
                            if (!ctx.mounted) return;
                            setSheet(() => generating = false);
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                              content: Text(e.message,
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text, fontSize: 13)),
                              backgroundColor: AppColors.card,
                              behavior: SnackBarBehavior.floating,
                            ));
                          }
                        },
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: generating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Generate',
                          style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Adds generated items as cards in [deck], skipping words the course
  /// already has (case-insensitive). Returns how many were added.
  int _addGeneratedCards(Deck deck, List<Map<String, dynamic>> items) {
    final existing = {
      for (final c in _cards)
        if (c.courseId == deck.courseId) c.word.trim().toLowerCase(),
    };
    final now = DateTime.now().millisecondsSinceEpoch;
    var added = 0;
    setState(() {
      for (final item in items) {
        final word = (item['word'] as String? ?? '').trim();
        if (word.isEmpty || existing.contains(word.toLowerCase())) continue;
        existing.add(word.toLowerCase());
        _cards.add(Flashcard(
          id: '${now + added}',
          word: word,
          translation: (item['translation'] as String? ?? '').trim(),
          wordType: item['wordType'] as String?,
          courseId: deck.courseId,
          deckIds: {deck.id},
        ));
        added++;
      }
    });
    if (added > 0) _saveCards();
    return added;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return switch (_view) {
      _View.hub         => _HubView(state: this),
      _View.deck        => _DeckHubView(state: this),
      _View.cardList    => _CardListView(state: this),
      _View.addCard     => _AddCardView(state: this),
      _View.learn       => _LearnView(state: this),
      _View.write       => _WriteView(state: this),
      _View.quiz        => _QuizView(state: this),
      _View.match       => _MatchView(state: this),
      _View.babelReview => _BabelReviewView(state: this),
      _View.babelLearn  => _BabelLearnView(state: this),
    };
  }
}

// ─── Hub (course level — shows decks) ────────────────────────────────────────

class _HubView extends StatelessWidget {
  final _FlashcardsScreenState state;
  const _HubView({required this.state});

  @override
  Widget build(BuildContext context) {
    final hasCourse = state._activeCourse != null;
    final decks = state._courseDecks;
    final totalCards = state._courseCards.length;
    final totalDue = state._courseCards.where((c) => c.isDue).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('talutalu',
                            style: GoogleFonts.cormorantGaramond(
                                color: AppColors.text,
                                fontSize: 26,
                                fontWeight: FontWeight.w300,
                                letterSpacing: -0.8)),
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 5, left: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.6),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    CourseBadge(
                        course: state._activeCourse,
                        onTap: state._showLanguageSheet),
                  ],
                ),
              ),
            ),
            if (!hasCourse)
              SliverFillRemaining(
                child: _NoCourseState(onTap: state._showLanguageSheet),
              )
            else ...[
              // Stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Row(
                    children: [
                      _StatChip(
                        label: 'Due today',
                        value: '$totalDue',
                        accent: totalDue > 0
                            ? AppColors.primary
                            : AppColors.text3,
                      ),
                      const SizedBox(width: 10),
                      _StatChip(label: 'Total', value: '$totalCards'),
                    ],
                  ),
                ),
              ),
              // Decks header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: Row(
                    children: [
                      Text('DECKS',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: state._showNewDeckDialog,
                        child: Row(
                          children: [
                            const Icon(Icons.add_rounded,
                                size: 14, color: AppColors.primary),
                            const SizedBox(width: 3),
                            Text('New deck',
                                style: GoogleFonts.dmSans(
                                    color: AppColors.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Decks grid
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final d = decks[i];
                      final count = d.isBabel
                          ? state._babelGroups().length
                          : state.cardsForDeck(d.id).length;
                      final due = d.isBabel ? 0 : state.dueForDeck(d.id);
                      return _DeckGridTile(
                        deck: d,
                        cardCount: count,
                        dueCount: due,
                        onTap: () => state._openDeck(d),
                        onLongPress: d.isVirtual
                            ? null
                            : () => _confirmDelete(context, d),
                      );
                    },
                    childCount: decks.length,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: hasCourse
          ? FloatingActionButton(
              heroTag: 'flashcards_hub_fab',
              onPressed: state._goToAddCard,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }

  void _confirmDelete(BuildContext context, Deck deck) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${deck.name}"?',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w500)),
        content: Text(
          'Cards in this deck will be moved to General.',
          style: GoogleFonts.dmSans(color: AppColors.text2, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.dmSans(color: AppColors.text2)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              state._deleteDeck(deck);
            },
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE57373)),
            child: Text('Delete',
                style: GoogleFonts.dmSans(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─── Deck hub (activity tiles for a specific deck) ────────────────────────────

class _DeckHubView extends StatelessWidget {
  final _FlashcardsScreenState state;
  const _DeckHubView({required this.state});

  @override
  Widget build(BuildContext context) {
    final deck = state._selectedDeck!;
    final rawCards = state._rawDeckCards;
    final cards = state._deckCards;
    final due = state._deckDueCards.length;
    final hasCards = cards.isNotEmpty;
    final availableTypes = state._deckAvailableTypes;
    final filters = state._activeTypeFilters;
    final isFiltered = filters.isNotEmpty;

    // Predefined order first, then any extra types from text imports, untyped last
    const typeOrder = ['noun', 'verb', 'adjective', 'phrase', 'other'];
    final orderedTypes = [
      ...typeOrder.where((t) => availableTypes.contains(t)),
      ...availableTypes.where((t) =>
          t != _FlashcardsScreenState._untypedKey && !typeOrder.contains(t)),
      if (availableTypes.contains(_FlashcardsScreenState._untypedKey))
        _FlashcardsScreenState._untypedKey,
    ];
    final showFilter = !deck.isAlphabet && !deck.isBabel && orderedTypes.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: state._goHome,
                      child: Icon(Icons.arrow_back_rounded,
                          color: AppColors.text, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(deck.name,
                          style: GoogleFonts.cormorantGaramond(
                              color: AppColors.text,
                              fontSize: 26,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    if (!deck.isVirtual) ...[
                      Tooltip(
                        message: deck.isPhrases
                            ? 'Generate phrases with AI'
                            : 'Generate vocabulary with AI',
                        child: GestureDetector(
                          onTap: () =>
                              state._showDeckGenerationSheet(context, deck),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Icon(Icons.auto_awesome_rounded,
                                size: 18, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (deck.isBabel)
                      GestureDetector(
                        onTap: () => state._showBabelBaseSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                state._activeCourse?['baseFlag'] ?? '',
                                style: const TextStyle(
                                    fontSize: 15, height: 1),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.expand_more_rounded,
                                  size: 16, color: AppColors.text3),
                            ],
                          ),
                        ),
                      )
                    else
                      CourseBadge(
                          course: state._activeCourse,
                          onTap: state._showLanguageSheet),
                  ],
                ),
              ),
            ),
            // Stats
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatChip(
                          label: 'Due',
                          value: '$due',
                          accent: due > 0 ? AppColors.primary : AppColors.text3),
                      const SizedBox(width: 10),
                      _StatChip(
                        label: isFiltered
                            ? 'of ${rawCards.length}'
                            : 'Cards',
                        value: '${cards.length}',
                        accent: isFiltered ? AppColors.primary : AppColors.text2,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => state._showSettingsSheet(context, deck.id),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Icon(Icons.tune_rounded,
                                size: 20, color: AppColors.text2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Type filter
            if (showFilter)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TYPE FILTER',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: orderedTypes.map((key) {
                            final isUntyped =
                                key == _FlashcardsScreenState._untypedKey;
                            final label = isUntyped ? 'Unclassified' : key;
                            final active = filters.contains(key);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: _FilterChip(
                                label: label,
                                selected: active,
                                onTap: () => state._toggleTypeFilter(key),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Activities grid
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final activities = deck.isAlphabet
                        ? _activities.where((a) => a.key != 'write').toList()
                        : deck.isBabel
                            ? _activities
                                .where((a) => a.key == 'review' || a.key == 'learn')
                                .toList()
                            : _activities;
                    final act = activities[i];
                    return _ActivityTile(
                      activity: act,
                      disabled: !hasCards && act.key != 'review',
                      dueCount: act.key == 'review' ? due : null,
                      onTap: () => state._openActivity(act.key),
                    );
                  },
                  childCount: deck.isAlphabet
                      ? _activities.where((a) => a.key != 'write').length
                      : deck.isBabel
                          ? 2
                          : _activities.length,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: deck.isAlphabet || deck.isBabel
          ? null
          : FloatingActionButton(
              heroTag: 'flashcards_deckhub_fab',
              onPressed: state._goToAddCard,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              child: const Icon(Icons.add_rounded),
            ),
    );
  }
}

// ─── Card list (Review activity) ─────────────────────────────────────────────

enum _LevelGroup {
  fresh(0, 0, 'New', Color(0xFF6B6880)),
  learning(1, 3, 'Learning', Color(0xFFE57373)),
  familiar(4, 6, 'Familiar', Color(0xFFFFA726)),
  known(7, 10, 'Known', Color(0xFF66BB6A));

  final int minLevel;
  final int maxLevel;
  final String label;
  final Color color;
  const _LevelGroup(this.minLevel, this.maxLevel, this.label, this.color);
  bool contains(int level) => level >= minLevel && level <= maxLevel;
}

enum _ReviewSort {
  wordAZ('A → Z'),
  wordZA('Z → A'),
  levelAsc('Weakest first'),
  levelDesc('Strongest first'),
  dateAsc('Oldest first'),
  dateDesc('Newest first');

  final String label;
  const _ReviewSort(this.label);
}

class _CardListView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _CardListView({required this.state});

  @override
  State<_CardListView> createState() => _CardListViewState();
}

class _CardListViewState extends State<_CardListView> {
  Set<_LevelGroup> _hiddenGroups = {};
  _ReviewSort _sort = _ReviewSort.wordAZ;
  final FlutterTts _tts = FlutterTts();
  late final Set<String> _newOnOpen;

  @override
  void initState() {
    super.initState();
    // Snapshot which cards were still unseen when Review was opened, so the
    // "NEW" badge shows for this visit — then immediately mark them seen so
    // it's gone the next time Review is opened for this deck.
    final fresh = widget.state._deckCards.where((c) => !c.seen).toList();
    _newOnOpen = fresh.map((c) => c.id).toSet();
    widget.state._markSeen(fresh);
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  bool get _hasActiveOptions =>
      _hiddenGroups.isNotEmpty || _sort != _ReviewSort.wordAZ;

  Future<void> _speak(String word, String langCode) async {
    await _tts.setLanguage(_ttsLocaleFor(langCode));
    await _tts.setSpeechRate(0.5);
    await _tts.speak(word);
  }

  void _showCardDetail(Flashcard card) {
    final course = widget.state._activeCourse;
    final targetCode = course?['targetCode'] ?? '';
    final userDecks =
        widget.state._courseDecks.where((d) => !d.isVirtual).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CardDetailSheet(
        card: card,
        userDecks: userDecks,
        targetFlag: course?['targetFlag'] ?? '',
        targetName: course?['targetName'] ?? '',
        baseFlag: course?['baseFlag'] ?? '',
        baseName: course?['baseName'] ?? '',
        onSpeak: () => _speak(card.word, targetCode),
        onSave: widget.state._updateCard,
        onDelete: () => widget.state._deleteCard(card),
      ),
    );
  }

  List<Flashcard> _process(List<Flashcard> cards) {
    var list = _hiddenGroups.isEmpty
        ? List<Flashcard>.from(cards)
        : cards
            .where((c) => !_hiddenGroups.any((g) => g.contains(c.masteryLevel)))
            .toList();
    switch (_sort) {
      case _ReviewSort.wordAZ:
        list.sort((a, b) => a.word.toLowerCase().compareTo(b.word.toLowerCase()));
      case _ReviewSort.wordZA:
        list.sort((a, b) => b.word.toLowerCase().compareTo(a.word.toLowerCase()));
      case _ReviewSort.levelAsc:
        list.sort((a, b) => a.masteryLevel.compareTo(b.masteryLevel));
      case _ReviewSort.levelDesc:
        list.sort((a, b) => b.masteryLevel.compareTo(a.masteryLevel));
      case _ReviewSort.dateAsc:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _ReviewSort.dateDesc:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return list;
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReviewOptionsSheet(listState: this),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = widget.state._selectedDeck!;
    final rawCards = widget.state._deckCards;
    final isTypeFiltered = widget.state._activeTypeFilters.isNotEmpty;
    final cards = _process(rawCards);
    final isFiltered = isTypeFiltered || _hasActiveOptions;
    final reversed = widget.state._settingsFor(deck.id).reversedReview;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.state._goToDeckHub,
                      child: Icon(Icons.arrow_back_rounded,
                          color: AppColors.text, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Review',
                              style: GoogleFonts.cormorantGaramond(
                                  color: AppColors.text,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              Text(deck.name,
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text3, fontSize: 12)),
                              if (isFiltered) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGlow,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: AppColors.primary
                                            .withOpacity(0.4)),
                                  ),
                                  child: Text('filtered',
                                      style: GoogleFonts.dmSans(
                                          color: AppColors.primarySoft,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showOptions(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _hasActiveOptions
                              ? AppColors.primaryGlow
                              : AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _hasActiveOptions
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Icon(Icons.tune_rounded,
                            size: 20,
                            color: _hasActiveOptions
                                ? AppColors.primary
                                : AppColors.text2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (cards.isEmpty)
              SliverFillRemaining(
                child: isFiltered
                    ? Center(
                        child: Text(
                          'No cards match the current filter.',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text2, fontSize: 14),
                        ),
                      )
                    : _EmptyDeckState(onAdd: widget.state._goToAddCard),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CardListItem(
                        card: cards[i],
                        reversed: reversed,
                        isNew: _newOnOpen.contains(cards[i].id),
                        onTap: () => _showCardDetail(cards[i]),
                        onLongPress: () => _showCardDetail(cards[i]),
                        onDelete: () => widget.state._deleteCard(cards[i]),
                      ),
                    ),
                    childCount: cards.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'flashcards_review_fab',
        onPressed: widget.state._goToAddCard,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}

class _ReviewOptionsSheet extends StatefulWidget {
  final _CardListViewState listState;
  const _ReviewOptionsSheet({required this.listState});

  @override
  State<_ReviewOptionsSheet> createState() => _ReviewOptionsSheetState();
}

class _ReviewOptionsSheetState extends State<_ReviewOptionsSheet> {
  late Set<_LevelGroup> _hidden;
  late _ReviewSort _sort;

  @override
  void initState() {
    super.initState();
    _hidden = Set.from(widget.listState._hiddenGroups);
    _sort = widget.listState._sort;
  }

  void _apply() {
    widget.listState.setState(() {
      widget.listState._hiddenGroups = Set.from(_hidden);
      widget.listState._sort = _sort;
    });
  }

  void _reset() {
    setState(() {
      _hidden = {};
      _sort = _ReviewSort.wordAZ;
    });
    _apply();
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(title,
            style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).padding.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                Text('Display options',
                    style: GoogleFonts.cormorantGaramond(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  child: Text('Reset',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3, fontSize: 13)),
                ),
              ],
            ),
            _section('DISPLAY'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _LevelGroup.values.map((g) {
                final shown = !_hidden.contains(g);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (shown) {
                        _hidden.add(g);
                      } else {
                        _hidden.remove(g);
                      }
                    });
                    _apply();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: shown
                          ? g.color.withValues(alpha: 0.15)
                          : AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: shown ? g.color : AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: shown ? g.color : AppColors.text3,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(g.label,
                            style: GoogleFonts.dmSans(
                                color:
                                    shown ? AppColors.text : AppColors.text3,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            _section('SORT'),
            ..._ReviewSort.values.map((s) {
              final active = _sort == s;
              return GestureDetector(
                onTap: () {
                  setState(() => _sort = s);
                  _apply();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        active
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 20,
                        color: active ? AppColors.primary : AppColors.text3,
                      ),
                      const SizedBox(width: 12),
                      Text(s.label,
                          style: GoogleFonts.dmSans(
                              color: active ? AppColors.text : AppColors.text2,
                              fontSize: 15,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w400)),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─── Add card view ────────────────────────────────────────────────────────────

class _AddCardView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _AddCardView({required this.state});

  @override
  State<_AddCardView> createState() => _AddCardViewState();
}

class _AddCardViewState extends State<_AddCardView> {
  final _wordCtrl = TextEditingController();
  final _transCtrl = TextEditingController();
  String? _wordType;
  final Set<String> _selectedDeckIds = {};

  static const _types = ['noun', 'verb', 'adjective', 'phrase', 'other'];

  @override
  void initState() {
    super.initState();
    // Pre-select the deck we navigated from (if it's a user deck)
    final d = widget.state._selectedDeck;
    if (d != null && !d.isVirtual) _selectedDeckIds.add(d.id);
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    _transCtrl.dispose();
    super.dispose();
  }

  void _back() {
    if (widget.state._selectedDeck != null) {
      widget.state._goToDeckHub();
    } else {
      widget.state._goHome();
    }
  }

  void _save() {
    final word = _wordCtrl.text.trim();
    final trans = _transCtrl.text.trim();
    if (word.isEmpty || trans.isEmpty) return;
    final card = Flashcard(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      word: word,
      translation: trans,
      wordType: _wordType,
      courseId: widget.state._courseId ?? 'unknown',
      deckIds: Set.from(_selectedDeckIds),
    );
    widget.state._addCard(card);
    _back();
  }

  @override
  Widget build(BuildContext context) {
    final userDecks =
        widget.state._courseDecks.where((d) => !d.isVirtual).toList();
    final course = widget.state._activeCourse;
    final targetFlag = course?['targetFlag'] ?? '';
    final targetName = course?['targetName'] ?? '';
    final baseFlag = course?['baseFlag'] ?? '';
    final baseName = course?['baseName'] ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: _back,
        ),
        title: Text('Add card',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 24,
                fontWeight: FontWeight.w500)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _langFieldLabel('WORD', targetFlag, targetName),
            const SizedBox(height: 10),
            TextField(
              controller: _wordCtrl,
              autofocus: true,
              style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 16),
              decoration: InputDecoration(
                  hintText: targetName.isNotEmpty ? targetName : 'Word'),
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 20),
            _langFieldLabel('TRANSLATION', baseFlag, baseName),
            const SizedBox(height: 10),
            TextField(
              controller: _transCtrl,
              style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 16),
              decoration: InputDecoration(
                  hintText: baseName.isNotEmpty ? baseName : 'Translation'),
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 20),
            _sLabel('TYPE (optional)'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _types.map((t) {
                final sel = _wordType == t;
                return GestureDetector(
                  onTap: () => setState(() => _wordType = sel ? null : t),
                  child: _Chip(
                      label: t, selected: sel, color: AppColors.primary),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _sLabel('DECKS'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // General is always included — show as locked
                _Chip(
                  label: 'General',
                  selected: true,
                  color: Deck.general('').accentColor,
                  locked: true,
                ),
                // User decks — multi-select
                ...userDecks.map((d) {
                  final sel = _selectedDeckIds.contains(d.id);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (sel) {
                        _selectedDeckIds.remove(d.id);
                      } else {
                        _selectedDeckIds.add(d.id);
                      }
                    }),
                    child: _Chip(
                        label: d.name, selected: sel, color: d.accentColor),
                  );
                }),
              ],
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Save card',
                    style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Write view ───────────────────────────────────────────────────────────────

/// Write-mode answer check. The stored answer can list several accepted
/// meanings separated by ",", "/" or ";" in any spacing ("over / above",
/// "x,y", "a; b"). The learner may type one meaning or several (same
/// separators, any order) — everything they typed just has to be among
/// the accepted variants.
bool matchesWriteAnswer(String input, String answer) {
  Set<String> variants(String s) => s
      .split(RegExp(r'[,;/]'))
      .map((v) => v.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '))
      .where((v) => v.isNotEmpty)
      .toSet();

  final accepted = variants(answer);
  final given = variants(input);
  return given.isNotEmpty && given.every(accepted.contains);
}

class _WriteView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _WriteView({required this.state});

  @override
  State<_WriteView> createState() => _WriteViewState();
}

class _WriteViewState extends State<_WriteView> {
  late List<Flashcard> _queue;
  int _index = 0;
  bool _reversed = false;
  bool? _correct;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = widget.state._settingsFor(widget.state._selectedDeck!.id);
    _reversed = s.reversedWrite;
    _queue = List<Flashcard>.from(
        (List.from(widget.state._deckCards)..shuffle())
            .take(s.writeQuestions));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _prompt =>
      _reversed ? _queue[_index].translation : _queue[_index].word;
  String get _answer =>
      _reversed ? _queue[_index].word : _queue[_index].translation;

  void _submit() {
    final isOk = matchesWriteAnswer(_ctrl.text, _answer);
    setState(() => _correct = isOk);
    _queue[_index].seen = true;
    if (isOk) {
      _queue[_index].applyEasy();
    } else {
      _queue[_index].applyAgain();
    }
    widget.state._updateCard(_queue[_index]);
  }

  void _next() {
    if (_index + 1 >= _queue.length) {
      setState(() => _index = _queue.length);
      return;
    }
    _ctrl.clear();
    setState(() {
      _index++;
      _correct = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final done = _index >= _queue.length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: widget.state._goToDeckHub,
        ),
        title: done
            ? null
            : Text('${_index + 1} / ${_queue.length}',
                style: GoogleFonts.dmSans(
                    color: AppColors.text2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
        centerTitle: true,
      ),
      body: done
          ? _SessionDone(
              label: 'Write complete!',
              onHome: widget.state._goToDeckHub,
              onRepeat: () => setState(() {
                    _queue = List<Flashcard>.from(
                        (List.from(widget.state._deckCards)..shuffle())
                            .take(widget.state._settingsFor(widget.state._selectedDeck!.id).writeQuestions));
                    _index = 0;
                    _correct = null;
                    _ctrl.clear();
                  }))
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    MediaQuery.of(context).viewInsets.bottom + 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: _index / _queue.length,
                      backgroundColor: AppColors.border,
                      color: AppColors.primary,
                      minHeight: 2,
                    ),
                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(_prompt,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cormorantGaramond(
                              color: AppColors.text,
                              fontSize: 36,
                              fontWeight: FontWeight.w400)),
                    ),
                    const SizedBox(height: 24),
                    if (_correct == null) ...[
                      TextField(
                        controller: _ctrl,
                        autofocus: true,
                        style: GoogleFonts.dmSans(
                            color: AppColors.text, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: _reversed
                              ? 'Type in target language…'
                              : 'Type translation…',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text('Check',
                              style: GoogleFonts.dmSans(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _correct!
                              ? const Color(0xFF1A3A1A)
                              : const Color(0xFF3A1A1A),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _correct!
                                  ? const Color(0xFF66BB6A)
                                  : const Color(0xFFE57373)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _correct! ? 'Correct!' : 'Incorrect',
                              style: GoogleFonts.dmSans(
                                  color: _correct!
                                      ? const Color(0xFF66BB6A)
                                      : const Color(0xFFE57373),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                            if (!_correct!) ...[
                              const SizedBox(height: 6),
                              Text('Answer: $_answer',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text,
                                      fontSize: 15)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text('Next',
                              style: GoogleFonts.dmSans(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

// ─── Quiz view ────────────────────────────────────────────────────────────────

class _QuizView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _QuizView({required this.state});

  @override
  State<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<_QuizView> {
  late List<Flashcard> _queue;
  late List<List<String>> _choices;
  int _index = 0;
  int? _selected;
  bool _answered = false;
  bool _reversed = false;

  @override
  void initState() {
    super.initState();
    _reversed = widget.state._settingsFor(widget.state._selectedDeck!.id).reversedQuiz;
    _build();
  }

  void _build() {
    final s = widget.state._settingsFor(widget.state._selectedDeck!.id);
    final cards = List.from(widget.state._deckCards)..shuffle();
    _queue = List<Flashcard>.from(cards.take(s.quizQuestions));
    _choices = _queue
        .map((c) => _makeChoices(c, List<Flashcard>.from(cards)))
        .toList();
  }

  List<String> _makeChoices(Flashcard correct, List<Flashcard> all) {
    final opts = widget.state._settingsFor(widget.state._selectedDeck!.id).quizOptions;
    final distractors = all
        .where((c) => c.id != correct.id)
        .map((c) => _reversed ? c.word : c.translation)
        .toList()
      ..shuffle();
    final answer = _reversed ? correct.word : correct.translation;
    return ([answer, ...distractors.take(opts - 1)]..shuffle());
  }

  void _pick(int i) {
    if (_answered) return;
    setState(() {
      _selected = i;
      _answered = true;
    });
    final correctAnswer =
        _reversed ? _queue[_index].word : _queue[_index].translation;
    final ok = _choices[_index][i] == correctAnswer;
    _queue[_index].seen = true;
    if (ok) {
      _queue[_index].applyEasy();
    } else {
      _queue[_index].applyAgain();
    }
    widget.state._updateCard(_queue[_index]);
  }

  void _next() {
    if (_index + 1 >= _queue.length) {
      setState(() => _index = _queue.length);
      return;
    }
    setState(() {
      _index++;
      _selected = null;
      _answered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.length < 2) {
      return _TooFewCards(
          message: 'Add at least 2 cards to play Quiz.',
          onClose: widget.state._goToDeckHub);
    }
    final done = _index >= _queue.length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: widget.state._goToDeckHub,
        ),
        title: done
            ? null
            : Text('${_index + 1} / ${_queue.length}',
                style: GoogleFonts.dmSans(
                    color: AppColors.text2,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
        centerTitle: true,
      ),
      body: done
          ? _SessionDone(
              label: 'Quiz complete!',
              onHome: widget.state._goToDeckHub,
              onRepeat: () => setState(() {
                    _build();
                    _index = 0;
                    _selected = null;
                    _answered = false;
                  }))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _index / _queue.length,
                    backgroundColor: AppColors.border,
                    color: AppColors.primary,
                    minHeight: 2,
                  ),
                  const SizedBox(height: 32),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                        _reversed
                            ? _queue[_index].translation
                            : _queue[_index].word,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.cormorantGaramond(
                            color: AppColors.text,
                            fontSize: 36,
                            fontWeight: FontWeight.w400)),
                  ),
                  const SizedBox(height: 24),
                  ...List.generate(_choices[_index].length, (i) {
                    final choice = _choices[_index][i];
                    final correctAnswer = _reversed
                        ? _queue[_index].word
                        : _queue[_index].translation;
                    final isCorrect = choice == correctAnswer;
                    Color border = AppColors.border;
                    Color bg = AppColors.card;
                    if (_answered) {
                      if (isCorrect) {
                        border = const Color(0xFF66BB6A);
                        bg = const Color(0xFF1A3A1A);
                      } else if (i == _selected) {
                        border = const Color(0xFFE57373);
                        bg = const Color(0xFF3A1A1A);
                      }
                    } else if (i == _selected) {
                      border = AppColors.primary;
                      bg = AppColors.primaryGlow;
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => _answered ? null : _pick(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: border),
                          ),
                          child: Text(choice,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.text, fontSize: 15)),
                        ),
                      ),
                    );
                  }),
                  if (_answered) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Next',
                            style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

// ─── Match view ───────────────────────────────────────────────────────────────

class _MatchView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _MatchView({required this.state});

  @override
  State<_MatchView> createState() => _MatchViewState();
}

class _MatchViewState extends State<_MatchView> {
  late List<Flashcard> _cards;
  late List<String> _left;
  late List<String> _right;
  int? _selL;
  int? _selR;
  final Set<int> _doneL = {};
  final Set<int> _doneR = {};
  int? _wrongL;
  int? _wrongR;
  int _round = 1;
  bool _reversed = false;

  @override
  void initState() {
    super.initState();
    _reversed = widget.state._settingsFor(widget.state._selectedDeck!.id).reversedMatch;
    _build();
  }

  void _build() {
    final pairs = widget.state._settingsFor(widget.state._selectedDeck!.id).matchPairs;
    final all = List.from(widget.state._deckCards)..shuffle();
    _cards = List<Flashcard>.from(all.take(pairs));
    _left = _cards.map((c) => _reversed ? c.translation : c.word).toList();
    _right =
        _cards.map((c) => _reversed ? c.word : c.translation).toList()
          ..shuffle();
    _selL = _selR = _wrongL = _wrongR = null;
    _doneL.clear();
    _doneR.clear();
  }

  void _tapL(int i) {
    if (_doneL.contains(i)) return;
    setState(() => _selL = i);
    _tryMatch();
  }

  void _tapR(int i) {
    if (_doneR.contains(i)) return;
    setState(() => _selR = i);
    _tryMatch();
  }

  void _tryMatch() {
    final l = _selL;
    final r = _selR;
    if (l == null || r == null) return;
    final card = _cards.firstWhere(
        (c) => (_reversed ? c.translation : c.word) == _left[l]);
    final rightAnswer = _reversed ? card.word : card.translation;
    if (rightAnswer == _right[r]) {
      setState(() {
        _doneL.add(l);
        _doneR.add(r);
        _selL = _selR = _wrongL = _wrongR = null;
      });
      card.seen = true;
      card.applyEasy();
      widget.state._updateCard(card);
    } else {
      setState(() {
        _wrongL = l;
        _wrongR = r;
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() => _selL = _selR = _wrongL = _wrongR = null);
        }
      });
      card.seen = true;
      card.applyAgain();
      widget.state._updateCard(card);
    }
  }

  bool get _allDone => _doneL.length == _cards.length;
  bool get _testDone => _round >= widget.state._settingsFor(widget.state._selectedDeck!.id).matchRounds;

  @override
  Widget build(BuildContext context) {
    if (widget.state._deckCards.length < 2) {
      return _TooFewCards(
          message: 'Add at least 2 cards to play Match.',
          onClose: widget.state._goToDeckHub);
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: widget.state._goToDeckHub,
        ),
        title: Text('Round $_round / ${widget.state._settingsFor(widget.state._selectedDeck!.id).matchRounds}',
            style: GoogleFonts.dmSans(
                color: AppColors.text2,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        centerTitle: true,
      ),
      body: _allDone
          ? (_testDone
              ? _SessionDone(
                  label: 'Match complete!',
                  onHome: widget.state._goToDeckHub,
                  onRepeat: () => setState(() {
                        _round = 1;
                        _build();
                      }))
              : _SessionDone(
                  label: 'Round $_round done!',
                  onHome: widget.state._goToDeckHub,
                  onRepeat: () => setState(() {
                        _round++;
                        _build();
                      })))
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: List.generate(_left.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MatchChip(
                            text: _left[i],
                            matched: _doneL.contains(i),
                            selected: _selL == i,
                            wrong: _wrongL == i,
                            onTap: _doneL.contains(i) ? null : () => _tapL(i),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: List.generate(_right.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MatchChip(
                            text: _right[i],
                            matched: _doneR.contains(i),
                            selected: _selR == i,
                            wrong: _wrongR == i,
                            onTap: _doneR.contains(i) ? null : () => _tapR(i),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── Learn view (gallery swipe) ───────────────────────────────────────────────

class _LearnView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _LearnView({required this.state});

  @override
  State<_LearnView> createState() => _LearnViewState();
}

class _LearnViewState extends State<_LearnView> {
  late List<Flashcard> _cards;
  int _index = 0;
  final PageController _pageCtrl = PageController();
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _cards = List.from(widget.state._deckCards)..shuffle();
  }

  @override
  void dispose() {
    _tts.stop();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _speak(String word, String langCode) async {
    await _tts.setLanguage(_ttsLocaleFor(langCode));
    await _tts.setSpeechRate(0.5);
    await _tts.speak(word);
  }

  void _showCardDetail(Flashcard card, String targetCode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FlashcardDetailSheet(
        card: card,
        onSpeak: () => _speak(card.word, targetCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.state._activeCourse;
    final targetCode = course?['targetCode'] ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: widget.state._goToDeckHub,
        ),
        title: Text('Learn',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w500)),
      ),
      body: _cards.isEmpty
          ? Center(
              child: Text('No cards yet.',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text2, fontSize: 16)))
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _cards.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (ctx, i) {
                      final card = _cards[i];
                      final displayWord = card.word;
                      final displayTranslation = card.translation;
                      final baseFlag = course?['baseFlag'] ?? '';
                      final targetFlag = course?['targetFlag'] ?? '';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (course != null)
                              Text(
                                '$baseFlag → $targetFlag',
                                style: const TextStyle(fontSize: 20),
                              ),
                            const SizedBox(height: 32),
                            Text(
                              displayWord,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.cormorantGaramond(
                                  color: AppColors.text,
                                  fontSize: 52,
                                  fontWeight: FontWeight.w300,
                                  height: 1.1),
                            ),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => _speak(card.word, targetCode),
                              child: Icon(Icons.volume_up_rounded,
                                  size: 20, color: AppColors.text3),
                            ),
                            const SizedBox(height: 12),
                            Container(
                                width: 48,
                                height: 1,
                                color: AppColors.border),
                            const SizedBox(height: 20),
                            Text(
                              displayTranslation,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.dmSans(
                                  color: AppColors.text2,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w400),
                            ),
                            if (card.wordType != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(20),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Text(card.wordType!,
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.text3,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ],
                            const SizedBox(height: 40),
                            _MasteryBar(card: card),
                            const SizedBox(height: 20),
                            GestureDetector(
                              onTap: () =>
                                  _showCardDetail(card, targetCode),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border:
                                      Border.all(color: AppColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.info_outline_rounded,
                                        size: 15, color: AppColors.text2),
                                    const SizedBox(width: 6),
                                    Text('Word info',
                                        style: GoogleFonts.dmSans(
                                            color: AppColors.text2,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      min(_cards.length, 8),
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _index == i ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _index == i
                              ? AppColors.primary
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _DeckGridTile extends StatelessWidget {
  final Deck deck;
  final int cardCount;
  final int dueCount;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _DeckGridTile({
    required this.deck,
    required this.cardCount,
    required this.dueCount,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: deck.accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    deck.isGeneral
                        ? Icons.auto_awesome_rounded
                        : deck.isFromTexts
                            ? Icons.article_rounded
                            : deck.isAlphabet
                                ? Icons.abc_rounded
                                : deck.isBabel
                                    ? Icons.language_rounded
                                    : deck.isPhrases
                                        ? Icons.format_quote_rounded
                                        : Icons.style_rounded,
                    size: 18,
                    color: deck.accentColor,
                  ),
                ),
                const Spacer(),
                if (dueCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$dueCount',
                        style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const Spacer(),
            Text(deck.name,
                style: GoogleFonts.dmSans(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(deck.isBabel ? '$cardCount words' : '$cardCount cards',
                style: GoogleFonts.dmSans(
                    color: AppColors.text3, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  const _StatChip({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: GoogleFonts.dmSans(
                  color: accent ?? AppColors.text2,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.dmSans(
                  color: AppColors.text3, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  final _Activity activity;
  final bool disabled;
  final int? dueCount;
  final VoidCallback? onTap;
  const _ActivityTile(
      {required this.activity,
      required this.disabled,
      this.dueCount,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: disabled ? 0.38 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: activity.color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(activity.icon,
                        size: 20, color: activity.color),
                  ),
                  const Spacer(),
                  if (dueCount != null && dueCount! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$dueCount',
                          style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
              const Spacer(),
              Text(activity.label,
                  style: GoogleFonts.dmSans(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(activity.sublabel,
                  style: GoogleFonts.dmSans(
                      color: AppColors.text3, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardListItem extends StatelessWidget {
  final Flashcard card;
  final bool reversed;
  final bool isNew;
  final VoidCallback? onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;
  const _CardListItem(
      {required this.card,
      this.reversed = false,
      this.isNew = false,
      this.onTap,
      required this.onLongPress,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(card.id),
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
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onLongPress();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: card.masteryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reversed ? card.translation : card.word,
                        style: GoogleFonts.dmSans(
                            color: AppColors.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text(reversed ? card.word : card.translation,
                        style: GoogleFonts.dmSans(
                            color: AppColors.text2, fontSize: 13)),
                  ],
                ),
              ),
              if (isNew) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: Text('NEW',
                      style: GoogleFonts.dmSans(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
              ],
              if (card.wordType != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(card.wordType!,
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3,
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
                ),
              ],
              const SizedBox(width: 8),
              Text('${card.masteryLevel}/10',
                  style: GoogleFonts.dmSans(
                      color: card.masteryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Card detail + edit sheet (Review) ─────────────────────────────────────────
// Combines what used to be two separate sheets (tap = info, long-press =
// edit) into one. Cards added from a text keep their word/type/decks locked
// to what the analyzer produced — only the translation can be corrected —
// since those fields are grounded in the source text, not user-authored.

class _CardDetailSheet extends StatefulWidget {
  final Flashcard card;
  final List<Deck> userDecks;
  final String targetFlag;
  final String targetName;
  final String baseFlag;
  final String baseName;
  final VoidCallback? onSpeak;
  final void Function(Flashcard updated) onSave;
  final VoidCallback onDelete;

  const _CardDetailSheet({
    required this.card,
    required this.userDecks,
    required this.targetFlag,
    required this.targetName,
    required this.baseFlag,
    required this.baseName,
    this.onSpeak,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<_CardDetailSheet> createState() => _CardDetailSheetState();
}

class _CardDetailSheetState extends State<_CardDetailSheet> {
  static const _types = ['noun', 'verb', 'adjective', 'phrase', 'other'];

  late final TextEditingController _wordCtrl;
  late final TextEditingController _transCtrl;
  String? _wordType;
  late Set<String> _deckIds;
  late List<Deck> _decks;

  bool get _locked => widget.card.fromTexts;

  @override
  void initState() {
    super.initState();
    _wordCtrl = TextEditingController(text: widget.card.word);
    _transCtrl = TextEditingController(text: widget.card.translation);
    _wordType = widget.card.wordType;
    _deckIds = Set.from(widget.card.deckIds);
    _decks = List.from(widget.userDecks);
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    _transCtrl.dispose();
    super.dispose();
  }

  Future<void> _createDeck() async {
    final courseId = widget.card.courseId;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('New deck',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w500)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 15),
          decoration: const InputDecoration(hintText: 'Deck name'),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.text2)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('Create',
                style:
                    GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final deck = Deck(
        id: '${DateTime.now().millisecondsSinceEpoch}', name: name, courseId: courseId);
    await AppStorage.instance.saveDecks([...AppStorage.instance.decks, deck]);
    setState(() {
      _decks.add(deck);
      _deckIds.add(deck.id);
    });
  }

  void _save() {
    final card = widget.card;
    card.translation = _transCtrl.text.trim();
    // Deck membership is organisational, not editing the word itself, so
    // it stays editable even for text-sourced cards — only word/type are
    // locked to what the analyzer produced.
    card.deckIds = Set.from(_deckIds);
    if (!_locked) {
      card.word = _wordCtrl.text.trim();
      card.wordType = _wordType;
    }
    widget.onSave(card);
    Navigator.pop(context);
  }

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
    final card = widget.card;
    final hasMorph = card.morph != null && card.morph!.isNotEmpty;
    final hasRoot = card.root != null && card.root!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
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
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: _locked
                              ? Text(card.word,
                                  style: GoogleFonts.cormorantGaramond(
                                      color: AppColors.text,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w400,
                                      height: 1.2))
                              : TextField(
                                  controller: _wordCtrl,
                                  style: GoogleFonts.cormorantGaramond(
                                      color: AppColors.text,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w400,
                                      height: 1.2),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.only(bottom: 6),
                                    border: UnderlineInputBorder(
                                        borderSide:
                                            BorderSide(color: AppColors.border)),
                                    enabledBorder: UnderlineInputBorder(
                                        borderSide:
                                            BorderSide(color: AppColors.border)),
                                    focusedBorder: const UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color: AppColors.primary,
                                            width: 1.5)),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onSpeak,
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
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            widget.onDelete();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Color(0xFFE57373), size: 20),
                          ),
                        ),
                      ],
                    ),
                    if (_locked) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.lock_outline_rounded,
                              size: 12, color: AppColors.text3),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                                'Added from a text — only the translation can be edited',
                                style: GoogleFonts.dmSans(
                                    color: AppColors.text3, fontSize: 11)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    _sLabel('TYPE'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _types.map((t) {
                        final sel = _wordType == t;
                        final chip = _Chip(
                            label: t, selected: sel, color: AppColors.primary);
                        return _locked
                            ? chip
                            : GestureDetector(
                                onTap: () => setState(
                                    () => _wordType = sel ? null : t),
                                child: chip,
                              );
                      }).toList(),
                    ),
                    if (hasMorph) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: card.morph!.entries
                            .map((e) => AttributeChip(
                                label: morphLabel(e.key, e.value)))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _langFieldLabel('TRANSLATION', widget.baseFlag, widget.baseName),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _transCtrl,
                      style: GoogleFonts.dmSans(
                          color: AppColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.all(18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    ),
                    if (hasRoot) ...[
                      const SizedBox(height: 18),
                      _sLabel('ROOT'),
                      const SizedBox(height: 8),
                      _infoBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.root!,
                                style: GoogleFonts.dmSans(
                                    color: AppColors.primarySoft,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            if (card.rootMeaning != null) ...[
                              const SizedBox(height: 4),
                              Text(card.rootMeaning!,
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text2,
                                      fontSize: 13,
                                      height: 1.4)),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _sLabel('DECKS'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Chip(
                          label: 'General',
                          selected: true,
                          color: Deck.general('').accentColor,
                          locked: true,
                        ),
                        if (card.fromTexts)
                          _Chip(
                            label: 'From Texts',
                            selected: true,
                            color: Deck.fromTexts('').accentColor,
                            locked: true,
                          ),
                        ..._decks.map((d) {
                          final sel = _deckIds.contains(d.id);
                          final chip = _Chip(
                              label: d.name, selected: sel, color: d.accentColor);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (sel) {
                                _deckIds.remove(d.id);
                              } else {
                                _deckIds.add(d.id);
                              }
                            }),
                            child: chip,
                          );
                        }),
                        GestureDetector(
                          onTap: _createDeck,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded,
                                    size: 14, color: AppColors.text2),
                                const SizedBox(width: 4),
                                Text('New deck',
                                    style: GoogleFonts.dmSans(
                                        color: AppColors.text2,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            size: 13, color: AppColors.text3),
                        const SizedBox(width: 6),
                        Text(
                          'Created ${_fmtDate(card.createdAt)}',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Save',
                            style: GoogleFonts.dmSans(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
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

// ── Card detail sheet ───────────────────────────────────────────────────────
// Mirrors the reader's word sheet (read_screen.dart _WordSheet) — same
// sections (word, attributes, translation, root) minus the deck picker,
// since this card is already in a deck. Shares morphLabel/AttributeChip
// with the reader via widgets/word_attributes.dart so the two don't drift.

class _FlashcardDetailSheet extends StatelessWidget {
  final Flashcard card;
  final VoidCallback? onSpeak;
  const _FlashcardDetailSheet({required this.card, this.onSpeak});

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
    final hasMorph = card.morph != null && card.morph!.isNotEmpty;
    final hasRoot = card.root != null && card.root!.isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
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
                          child: Text(card.word,
                              style: GoogleFonts.cormorantGaramond(
                                  color: AppColors.text,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w400,
                                  height: 1.0)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: onSpeak,
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
                    if (card.wordType != null) ...[
                      const SizedBox(height: 6),
                      Text(card.wordType!,
                          style: GoogleFonts.dmSans(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5)),
                    ],
                    if (hasMorph) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: card.morph!.entries
                            .map((e) => AttributeChip(
                                label: morphLabel(e.key, e.value)))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _sectionLabel('TRANSLATION'),
                    const SizedBox(height: 8),
                    _infoBox(
                      child: Text(card.translation,
                          style: GoogleFonts.dmSans(
                              color: AppColors.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w500)),
                    ),
                    if (hasRoot) ...[
                      const SizedBox(height: 18),
                      _sectionLabel('ROOT'),
                      const SizedBox(height: 8),
                      _infoBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(card.root!,
                                style: GoogleFonts.dmSans(
                                    color: AppColors.primarySoft,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            if (card.rootMeaning != null) ...[
                              const SizedBox(height: 4),
                              Text(card.rootMeaning!,
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text2,
                                      fontSize: 13,
                                      height: 1.4)),
                            ],
                          ],
                        ),
                      ),
                    ],
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

class _MatchChip extends StatelessWidget {
  final String text;
  final bool matched;
  final bool selected;
  final bool wrong;
  final VoidCallback? onTap;
  const _MatchChip(
      {required this.text,
      required this.matched,
      required this.selected,
      required this.wrong,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    Color bg = AppColors.card;
    Color border = AppColors.border;
    Color textColor = AppColors.text;
    if (matched) {
      bg = const Color(0xFF1A3A1A);
      border = const Color(0xFF66BB6A);
      textColor = const Color(0xFF66BB6A);
    } else if (wrong) {
      bg = const Color(0xFF3A1A1A);
      border = const Color(0xFFE57373);
    } else if (selected) {
      bg = AppColors.primaryGlow;
      border = AppColors.primary;
    }
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _MasteryBar extends StatelessWidget {
  final Flashcard card;
  const _MasteryBar({required this.card});

  @override
  Widget build(BuildContext context) {
    final level = card.masteryLevel;
    final color = card.masteryColor;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Mastery',
                style: GoogleFonts.dmSans(
                    color: AppColors.text3, fontSize: 12)),
            const SizedBox(width: 8),
            Text('$level/10',
                style: GoogleFonts.dmSans(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        // 10-segment indicator
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(10, (i) {
            final filled = i < level;
            return Container(
              width: 14,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: filled ? color : AppColors.border,
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SessionDone extends StatelessWidget {
  final String label;
  final VoidCallback onHome;
  final VoidCallback onRepeat;
  const _SessionDone(
      {required this.label, required this.onHome, required this.onRepeat});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.primaryGlow,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.primary, size: 40),
            ),
            const SizedBox(height: 24),
            Text(label,
                style: GoogleFonts.cormorantGaramond(
                    color: AppColors.text,
                    fontSize: 32,
                    fontWeight: FontWeight.w400)),
            const SizedBox(height: 36),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onRepeat,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Again',
                        style: GoogleFonts.dmSans(
                            color: AppColors.text2,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: onHome,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Done',
                        style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TooFewCards extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _TooFewCards({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: onClose,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  color: AppColors.text2, fontSize: 16)),
        ),
      ),
    );
  }
}

class _NoCourseState extends StatelessWidget {
  final VoidCallback onTap;
  const _NoCourseState({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined,
                size: 56, color: AppColors.text3),
            const SizedBox(height: 20),
            Text('Select a course',
                style: GoogleFonts.cormorantGaramond(
                    color: AppColors.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w400)),
            const SizedBox(height: 10),
            Text(
              'Flashcards are organised per course.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  color: AppColors.text2, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Choose course',
                  style: GoogleFonts.dmSans(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDeckState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyDeckState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_card_rounded,
              size: 48, color: AppColors.text3),
          const SizedBox(height: 16),
          Text('No cards yet',
              style: GoogleFonts.cormorantGaramond(
                  color: AppColors.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w400)),
          const SizedBox(height: 8),
          Text('Add your first card to start.',
              style:
                  GoogleFonts.dmSans(color: AppColors.text2, fontSize: 14)),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, color: AppColors.primary),
            label: Text('Add a card',
                style: GoogleFonts.dmSans(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final bool locked;
  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.18) : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: GoogleFonts.dmSans(
                  color: selected ? color : AppColors.text2,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          if (locked) ...[
            const SizedBox(width: 4),
            Icon(Icons.lock_outline_rounded,
                size: 10,
                color: selected ? color.withOpacity(0.7) : AppColors.text3),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGlow : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            color: selected ? AppColors.primarySoft : AppColors.text2,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

Widget _sLabel(String text) => Text(text,
    style: GoogleFonts.dmSans(
        color: AppColors.text3,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2));

Widget _langFieldLabel(String label, String flag, String name) => Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label,
            style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
        if (flag.isNotEmpty || name.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(flag, style: const TextStyle(fontSize: 13)),
          if (name.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(name,
                style: GoogleFonts.dmSans(
                    color: AppColors.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ],
    );

// ─── Babel — Review ───────────────────────────────────────────────────────────

enum _BabelSort {
  wordAZ('A → Z'),
  wordZA('Z → A'),
  masteryDesc('Highest mastery first'),
  masteryAsc('Lowest mastery first'),
  translationsDesc('Most translations first'),
  translationsAsc('Fewest translations first');

  final String label;
  const _BabelSort(this.label);
}

class _BabelReviewView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _BabelReviewView({required this.state});
  @override
  State<_BabelReviewView> createState() => _BabelReviewViewState();
}

class _BabelReviewViewState extends State<_BabelReviewView> {
  late final List<_BabelGroup> _rawGroups;
  late final List<Map<String, String>> _sameCourses;
  int? _expanded;
  _BabelSort? _sort;
  final FlutterTts _tts = FlutterTts();

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String word, String langCode) async {
    await _tts.setLanguage(_ttsLocaleFor(langCode));
    await _tts.setSpeechRate(0.5);
    await _tts.speak(word);
  }

  void _showCardDetail(Flashcard card, String targetCode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FlashcardDetailSheet(
        card: card,
        onSpeak: () => _speak(card.word, targetCode),
      ),
    );
  }

  static double _avgMastery(_BabelGroup g) {
    final levels = g.byCourseId.values.map((c) => c.masteryLevel);
    if (levels.isEmpty) return 0;
    return levels.reduce((a, b) => a + b) / levels.length;
  }

  List<_BabelGroup> get _groups {
    final list = List<_BabelGroup>.from(_rawGroups);
    switch (_sort) {
      case _BabelSort.wordAZ:
        list.sort((a, b) =>
            a.baseWord.toLowerCase().compareTo(b.baseWord.toLowerCase()));
      case _BabelSort.wordZA:
        list.sort((a, b) =>
            b.baseWord.toLowerCase().compareTo(a.baseWord.toLowerCase()));
      case _BabelSort.masteryDesc:
        list.sort((a, b) => _avgMastery(b).compareTo(_avgMastery(a)));
      case _BabelSort.masteryAsc:
        list.sort((a, b) => _avgMastery(a).compareTo(_avgMastery(b)));
      case _BabelSort.translationsDesc:
        list.sort((a, b) =>
            b.byCourseId.length.compareTo(a.byCourseId.length));
      case _BabelSort.translationsAsc:
        list.sort((a, b) =>
            a.byCourseId.length.compareTo(b.byCourseId.length));
      case null:
        break;
    }
    return list;
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BabelOptionsSheet(
        current: _sort,
        onChanged: (s) => setState(() {
          _sort = s;
          _expanded = null;
        }),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _rawGroups = widget.state._babelGroups();
    final base = widget.state._activeCourse?['baseCode'] ?? '';
    _sameCourses = widget.state._pickerCourses
        .where((c) => c['baseCode'] == base)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: widget.state._goToDeckHub,
                      child: Icon(Icons.arrow_back_rounded,
                          color: AppColors.text, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Babel',
                            style: GoogleFonts.cormorantGaramond(
                                color: AppColors.text,
                                fontSize: 26,
                                fontWeight: FontWeight.w500)),
                        Text('Review · ${groups.length} words',
                            style: GoogleFonts.dmSans(
                                color: AppColors.text3, fontSize: 12)),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showOptions(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _sort != null
                              ? AppColors.primaryGlow
                              : AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _sort != null
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Icon(Icons.tune_rounded,
                            size: 20,
                            color: _sort != null
                                ? AppColors.primary
                                : AppColors.text2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () =>
                          widget.state._showBabelBaseSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.state._activeCourse?['baseFlag'] ?? '',
                              style:
                                  const TextStyle(fontSize: 15, height: 1),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.expand_more_rounded,
                                size: 16, color: AppColors.text3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (groups.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.language_rounded,
                          size: 48, color: AppColors.text3),
                      const SizedBox(height: 16),
                      Text('No shared words yet',
                          style: GoogleFonts.cormorantGaramond(
                              color: AppColors.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w400)),
                      const SizedBox(height: 8),
                      Text(
                          'Add the same word in two or more\nof your courses to see it here.',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text2,
                              fontSize: 13,
                              height: 1.5),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _BabelWordTile(
                      group: groups[i],
                      sameCourses: _sameCourses,
                      expanded: _expanded == i,
                      onTap: () => setState(
                          () => _expanded = _expanded == i ? null : i),
                      onWordTap: _showCardDetail,
                    ),
                    childCount: groups.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Babel — options sheet ────────────────────────────────────────────────────

class _BabelOptionsSheet extends StatefulWidget {
  final _BabelSort? current;
  final void Function(_BabelSort?) onChanged;
  const _BabelOptionsSheet(
      {required this.current, required this.onChanged});

  @override
  State<_BabelOptionsSheet> createState() => _BabelOptionsSheetState();
}

class _BabelOptionsSheetState extends State<_BabelOptionsSheet> {
  _BabelSort? _sort;

  @override
  void initState() {
    super.initState();
    _sort = widget.current;
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(title,
            style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(
            children: [
              Text('Sort',
                  style: GoogleFonts.cormorantGaramond(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() => _sort = null);
                  widget.onChanged(null);
                },
                child: Text('Reset',
                    style: GoogleFonts.dmSans(
                        color: AppColors.text3, fontSize: 13)),
              ),
            ],
          ),
          _section('ORDER'),
          ..._BabelSort.values.map((s) {
            final active = _sort == s;
            return GestureDetector(
              onTap: () {
                setState(() => _sort = s);
                widget.onChanged(s);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      active
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: active ? AppColors.primary : AppColors.text3,
                    ),
                    const SizedBox(width: 12),
                    Text(s.label,
                        style: GoogleFonts.dmSans(
                            color: active ? AppColors.text : AppColors.text2,
                            fontSize: 15,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400)),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _BabelWordTile extends StatelessWidget {
  final _BabelGroup group;
  final List<Map<String, String>> sameCourses;
  final bool expanded;
  final VoidCallback onTap;
  final void Function(Flashcard card, String targetCode) onWordTap;

  const _BabelWordTile({
    required this.group,
    required this.sameCourses,
    required this.expanded,
    required this.onTap,
    required this.onWordTap,
  });

  String _courseId(Map<String, String> c) =>
      '${c['baseCode']}_${c['targetCode']}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: expanded ? AppColors.primary : AppColors.border,
              width: expanded ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.baseWord,
                        style: GoogleFonts.cormorantGaramond(
                            color: AppColors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    Text(
                      '${group.byCourseId.length}/${sameCourses.length}',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded,
                          size: 20, color: AppColors.text2),
                    ),
                  ],
                ),
              ),
              // Expanded translations
              if (expanded) ...[
                Container(
                  height: 1,
                  color: AppColors.border,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                ),
                ...sameCourses.map((course) {
                  final cId = _courseId(course);
                  final card = group.byCourseId[cId];
                  final row = Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Text(course['targetFlag'] ?? '',
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: card != null
                              ? Text(group.displayFor(card),
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500))
                              : Text('not learned yet',
                                  style: GoogleFonts.dmSans(
                                      color: AppColors.text3,
                                      fontSize: 14,
                                      fontStyle: FontStyle.italic)),
                        ),
                        if (card != null) ...[
                          const SizedBox(width: 8),
                          Text('${card.masteryLevel}/10',
                              style: GoogleFonts.dmSans(
                                  color: card.masteryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  );
                  if (card == null) return row;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        onWordTap(card, course['targetCode'] ?? ''),
                    child: row,
                  );
                }),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Babel — Learn ────────────────────────────────────────────────────────────

class _BabelLearnView extends StatefulWidget {
  final _FlashcardsScreenState state;
  const _BabelLearnView({required this.state});
  @override
  State<_BabelLearnView> createState() => _BabelLearnViewState();
}

class _BabelLearnViewState extends State<_BabelLearnView> {
  late final List<_BabelGroup> _groups;
  late final List<Map<String, String>> _sameCourses;
  int _wordIndex = 0;
  final PageController _wordCtrl = PageController();

  @override
  void initState() {
    super.initState();
    _groups = widget.state._babelGroups();
    final base = widget.state._activeCourse?['baseCode'] ?? '';
    _sameCourses = widget.state._pickerCourses
        .where((c) => c['baseCode'] == base)
        .toList();
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _courseData(String courseId) =>
      _sameCourses.firstWhere(
        (c) => '${c['baseCode']}_${c['targetCode']}' == courseId,
        orElse: () => {'targetFlag': '', 'targetName': courseId},
      );

  @override
  Widget build(BuildContext context) {
    final baseFlag = widget.state._activeCourse?['baseFlag'] ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: AppColors.text),
          onPressed: widget.state._goToDeckHub,
        ),
        title: Text('Learn',
            style: GoogleFonts.cormorantGaramond(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w500)),
      ),
      body: _groups.isEmpty
          ? Center(
              child: Text('No words yet.',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text2, fontSize: 16)))
          : Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _wordCtrl,
                    itemCount: _groups.length,
                    onPageChanged: (i) => setState(() => _wordIndex = i),
                    itemBuilder: (ctx, i) => _BabelWordPage(
                      group: _groups[i],
                      baseFlag: baseFlag,
                      courseData: _courseData,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      min(_groups.length, 8),
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _wordIndex == i ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _wordIndex == i
                              ? AppColors.primary
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _BabelWordPage extends StatefulWidget {
  final _BabelGroup group;
  final String baseFlag;
  final Map<String, String> Function(String courseId) courseData;

  const _BabelWordPage({
    required this.group,
    required this.baseFlag,
    required this.courseData,
  });

  @override
  State<_BabelWordPage> createState() => _BabelWordPageState();
}

class _BabelWordPageState extends State<_BabelWordPage> {
  int _langIndex = 0;
  final FlutterTts _tts = FlutterTts();

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _speak(String word, String langCode) async {
    await _tts.setLanguage(_ttsLocaleFor(langCode));
    await _tts.setSpeechRate(0.5);
    await _tts.speak(word);
  }

  List<MapEntry<String, Flashcard>> get _entries =>
      widget.group.byCourseId.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final showIndicator = entries.length > 1;
    return Stack(
      children: [
        PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: entries.length,
          onPageChanged: (i) => setState(() => _langIndex = i),
          itemBuilder: (ctx, i) {
            final courseId = entries[i].key;
            final card = entries[i].value;
            final data = widget.courseData(courseId);
            final targetFlag = data['targetFlag'] ?? '';
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  28, 16, showIndicator ? 40 : 28, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$targetFlag → ${widget.baseFlag}',
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    card.word,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cormorantGaramond(
                        color: AppColors.text,
                        fontSize: 52,
                        fontWeight: FontWeight.w300,
                        height: 1.1),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () =>
                        _speak(card.word, data['targetCode'] ?? ''),
                    child: Icon(Icons.volume_up_rounded,
                        size: 20, color: AppColors.text3),
                  ),
                  const SizedBox(height: 16),
                  Container(width: 48, height: 1, color: AppColors.border),
                  const SizedBox(height: 20),
                  Text(
                    card.translation,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                        color: AppColors.text2,
                        fontSize: 22,
                        fontWeight: FontWeight.w400),
                  ),
                  const SizedBox(height: 48),
                  _MasteryBar(card: card),
                ],
              ),
            );
          },
        ),
        if (showIndicator)
          Positioned(
            right: 10,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(entries.length, (i) {
                  final active = i == _langIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 4,
                    height: active ? 20 : 6,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: active ? AppColors.primary : AppColors.border,
                    ),
                  );
                }),
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Settings sheet ───────────────────────────────────────────────────────────

class _SettingsSheet extends StatefulWidget {
  final _FlashcardsScreenState state;
  final String deckId;
  const _SettingsSheet({required this.state, required this.deckId});
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late bool _revReview;
  late bool _revWrite;
  late bool _revQuiz;
  late bool _revMatch;
  late double _writeQ;
  late double _quizQ;
  late double _quizOpts;
  late double _matchRounds;
  late double _matchPairs;
  late Set<String> _hiddenCodes;

  FlashcardsSettings get _s =>
      widget.state._settingsFor(widget.deckId);

  bool get _isAlphabet => widget.deckId == Deck.alphabetId;
  bool get _isBabel => widget.deckId == Deck.babelId;

  List<Map<String, String>> _babelTargets() {
    final baseCode = widget.state._activeCourse?['baseCode'] ?? '';
    return widget.state._pickerCourses
        .where((c) => c['baseCode'] == baseCode)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _revReview = _isAlphabet ? false : _s.reversedReview;
    _revWrite = _s.reversedWrite;
    _revQuiz = _s.reversedQuiz;
    _revMatch = _s.reversedMatch;
    _writeQ = _s.writeQuestions.toDouble();
    _quizQ = _s.quizQuestions.toDouble();
    _quizOpts = _s.quizOptions.toDouble();
    _matchRounds = _s.matchRounds.toDouble();
    _matchPairs = _s.matchPairs.toDouble();
    _hiddenCodes = Set.from(_s.hiddenTargetCodes);
  }

  void _apply() {
    _s.reversedReview = _revReview;
    _s.reversedWrite = _revWrite;
    _s.reversedQuiz = _revQuiz;
    _s.reversedMatch = _revMatch;
    _s.writeQuestions = _writeQ.round();
    _s.quizQuestions = _quizQ.round();
    _s.quizOptions = _quizOpts.round();
    _s.matchRounds = _matchRounds.round();
    _s.matchPairs = _matchPairs.round();
    _s.hiddenTargetCodes = Set.from(_hiddenCodes);
    widget.state._saveDeckSettings();
  }

  void _reset() {
    setState(() {
      _revReview = false;
      _revWrite = true;
      _revQuiz = true;
      _revMatch = true;
      _writeQ = 20;
      _quizQ = 20;
      _quizOpts = 4;
      _matchRounds = 3;
      _matchPairs = 6;
      _hiddenCodes = {};
    });
    _apply();
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 2),
        child: Text(title,
            style: GoogleFonts.dmSans(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2)),
      );

  Widget _directionToggle(bool value, void Function(bool) onChanged) {
    final course = widget.state._activeCourse;
    final base = course?['baseFlag'] ?? '';
    final target = course?['targetFlag'] ?? '';
    final flagDesc = value
        ? '${base.isNotEmpty ? "$base " : ""}Translation → ${target.isNotEmpty ? "$target " : ""}word'
        : '${target.isNotEmpty ? "$target " : ""}Word → ${base.isNotEmpty ? "$base " : ""}translation';
    return Row(
      children: [
        Expanded(
          child: Text(
            flagDesc,
            style: GoogleFonts.dmSans(
                color: AppColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w500),
          ),
        ),
        Switch(
          value: value,
          onChanged: (v) {
            setState(() => onChanged(v));
            _apply();
          },
          activeThumbColor: AppColors.primary,
          activeTrackColor: AppColors.primaryGlow,
        ),
      ],
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      int divisions, void Function(double) setter) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style:
                    GoogleFonts.dmSans(color: AppColors.text, fontSize: 14)),
            const Spacer(),
            Text('${value.round()}',
                style: GoogleFonts.dmSans(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.primary,
            inactiveColor: AppColors.border,
            onChanged: (v) {
              setState(() => setter(v));
              _apply();
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).padding.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Settings',
                    style: GoogleFonts.cormorantGaramond(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                TextButton(
                  onPressed: _reset,
                  child: Text('Reset',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3, fontSize: 13)),
                ),
              ],
            ),
            if (_isBabel) ...[
              _section('LANGUAGES'),
              const SizedBox(height: 2),
              ..._babelTargets().map((c) {
                final code = c['targetCode'] ?? '';
                final shown = !_hiddenCodes.contains(code);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (shown) {
                        _hiddenCodes.add(code);
                      } else {
                        _hiddenCodes.remove(code);
                      }
                    });
                    _apply();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: AppColors.border, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Text(c['targetFlag'] ?? '',
                            style:
                                const TextStyle(fontSize: 20, height: 1.2)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(c['targetName'] ?? '',
                              style: GoogleFonts.dmSans(
                                  color: AppColors.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Switch(
                          value: shown,
                          onChanged: (v) {
                            setState(() =>
                                v ? _hiddenCodes.remove(code) : _hiddenCodes.add(code));
                            _apply();
                          },
                          activeThumbColor: AppColors.primary,
                          activeTrackColor: AppColors.primaryGlow,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ] else ...[
              if (!_isAlphabet) _section('REVIEW'),
              if (!_isAlphabet) _directionToggle(_revReview, (v) => _revReview = v),
              _section('WRITE'),
              if (!_isAlphabet) _directionToggle(_revWrite, (v) => _revWrite = v),
              _sliderRow('Questions per test', _writeQ, 5, 50, 9,
                  (v) => _writeQ = v),
              _section('QUIZ'),
              if (!_isAlphabet) _directionToggle(_revQuiz, (v) => _revQuiz = v),
              _sliderRow('Questions per test', _quizQ, 5, 50, 9,
                  (v) => _quizQ = v),
              _sliderRow('Answer options', _quizOpts, 2, 6, 4,
                  (v) => _quizOpts = v),
              _section('MATCH'),
              if (!_isAlphabet) _directionToggle(_revMatch, (v) => _revMatch = v),
              _sliderRow('Rounds per test', _matchRounds, 1, 10, 9,
                  (v) => _matchRounds = v),
              _sliderRow('Pairs per round', _matchPairs, 2, 10, 8,
                  (v) => _matchPairs = v),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Deck creation / generation chips ─────────────────────────────────────────

class _DeckTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _DeckTypeChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGlow : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? AppColors.primary : AppColors.text2),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.dmSans(
                    color: selected ? AppColors.primarySoft : AppColors.text2,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SheetChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGlow : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Text(label,
            style: GoogleFonts.dmSans(
                color: selected ? AppColors.primarySoft : AppColors.text2,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}
