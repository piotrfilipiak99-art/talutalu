import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/app_storage.dart';
import '../models/flashcard.dart';
import '../models/deck.dart';
import '../models/explain_request.dart';
import '../models/text_token.dart';
import '../widgets/course_badge.dart';
import '../widgets/word_attributes.dart';
import 'language_screen.dart';

// Mock data — will be replaced with real AI calls
const _mockPolishText =
    'Warszawa jest stolicą Polski i największym miastem w kraju. Miasto leży nad Wisłą i ma ponad 1,7 miliona mieszkańców. Historia Warszawy sięga XIII wieku, choć prawdziwy rozkwit nastąpił w XVI i XVII stuleciu. Po zniszczeniach II wojny światowej miasto zostało odbudowane z niezwykłą starannością.';

const _mockEnglishText =
    'Warsaw is the capital of Poland and the largest city in the country. The city lies on the Vistula River and has over 1.7 million inhabitants. Warsaw\'s history dates back to the 13th century, although its real flourishing occurred in the 16th and 17th centuries. After the destruction of World War II, the city was rebuilt with extraordinary care.';

// Per-token annotation for the mock paragraph — schema scaffold for what a
// real AI generation call would eventually return per word (lemma, UD part
// of speech, UD morphological features, translation in the course's base
// language). Ordered 1:1 with _mockPolishText.split(' '); a real backend
// would send its own tokens, but the rest of the pipeline (offset
// computation, sentence indexing, repeat-for-length, append-for-continue)
// is written against this shape either way. Punctuation stays attached to
// the preceding word (not split into its own token) to match how the
// reader already treats space-separated chunks as one tappable unit.
class _MockWord {
  final String lemma;
  final String pos;
  final String? translation;
  final String? lemmaTranslation;
  final Map<String, String> morph;
  final String? root;
  final String? rootMeaning;
  const _MockWord(this.lemma, this.pos,
      {this.translation,
      this.lemmaTranslation,
      this.morph = const {},
      this.root,
      this.rootMeaning});
}

final List<_MockWord> _mockPolishWords = [
  _MockWord('Warszawa', 'PROPN', translation: 'Warsaw', lemmaTranslation: 'Warsaw', morph: {'Case': 'Nom', 'Gender': 'Fem'}),
  _MockWord('być', 'VERB', translation: 'is', lemmaTranslation: 'to be', morph: {'Person': '3', 'Number': 'Sing', 'Tense': 'Pres'}, root: 'by-', rootMeaning: 'to exist, to be'),
  _MockWord('stolica', 'NOUN', translation: 'capital', lemmaTranslation: 'capital', morph: {'Case': 'Ins', 'Number': 'Sing', 'Gender': 'Fem'}, root: 'stoł-', rootMeaning: "throne, seat (historically from 'stół' — table)"),
  _MockWord('Polska', 'PROPN', translation: 'of Poland', lemmaTranslation: 'Poland', morph: {'Case': 'Gen', 'Gender': 'Fem'}, root: 'Pol-', rootMeaning: "field — traditionally linked to 'pole' (the Polanie, \"field-dwellers\")"),
  _MockWord('i', 'CCONJ', translation: 'and', lemmaTranslation: 'and'),
  _MockWord('duży', 'ADJ', translation: 'largest', lemmaTranslation: 'big, large', morph: {'Case': 'Ins', 'Number': 'Sing', 'Gender': 'Masc', 'Degree': 'Sup'}, root: 'więk-', rootMeaning: "great, large — from 'wielki'; duży's comparative/superlative are suppletive and borrow this root, not duży's own"),
  _MockWord('miasto', 'NOUN', translation: 'city', lemmaTranslation: 'city', morph: {'Case': 'Ins', 'Number': 'Sing', 'Gender': 'Neut'}, root: 'miast-', rootMeaning: "place — related to 'miejsce'"),
  _MockWord('w', 'ADP', translation: 'in', lemmaTranslation: 'in'),
  _MockWord('kraj', 'NOUN', translation: 'country', lemmaTranslation: 'country', morph: {'Case': 'Loc', 'Number': 'Sing', 'Gender': 'Masc'}, root: 'kraj-', rootMeaning: "a cut, a bounded piece of land — from 'krajać' (to cut)"),
  _MockWord('miasto', 'NOUN', translation: 'The city', lemmaTranslation: 'city', morph: {'Case': 'Nom', 'Number': 'Sing', 'Gender': 'Neut'}, root: 'miast-', rootMeaning: "place — related to 'miejsce'"),
  _MockWord('leżeć', 'VERB', translation: 'lies', lemmaTranslation: 'to lie, to be located', morph: {'Person': '3', 'Number': 'Sing', 'Tense': 'Pres'}, root: 'leż-', rootMeaning: 'to lie, to recline'),
  _MockWord('nad', 'ADP', translation: 'on', lemmaTranslation: 'above, over'),
  _MockWord('Wisła', 'PROPN', translation: 'the Vistula River', lemmaTranslation: 'the Vistula River', morph: {'Case': 'Ins', 'Gender': 'Fem'}),
  _MockWord('i', 'CCONJ', translation: 'and', lemmaTranslation: 'and'),
  _MockWord('mieć', 'VERB', translation: 'has', lemmaTranslation: 'to have', morph: {'Person': '3', 'Number': 'Sing', 'Tense': 'Pres'}, root: 'mie-', rootMeaning: 'to have, to possess'),
  _MockWord('ponad', 'ADP', translation: 'over', lemmaTranslation: 'over, more than'),
  _MockWord('1,7', 'NUM', translation: '1.7', lemmaTranslation: '1.7'),
  _MockWord('milion', 'NUM', translation: 'million', lemmaTranslation: 'million', morph: {'Case': 'Gen', 'Number': 'Sing'}, root: 'mili-', rootMeaning: "thousand — Latin 'mille', via French/Italian 'million'"),
  _MockWord('mieszkaniec', 'NOUN', translation: 'inhabitants', lemmaTranslation: 'inhabitant', morph: {'Case': 'Gen', 'Number': 'Plur', 'Gender': 'Masc'}, root: 'mieszka-', rootMeaning: "to live, to reside — from 'mieszkać'"),
  _MockWord('historia', 'NOUN', translation: 'History', lemmaTranslation: 'history', morph: {'Case': 'Nom', 'Number': 'Sing', 'Gender': 'Fem'}, root: 'histor-', rootMeaning: "inquiry, knowledge — Greek 'historía'"),
  _MockWord('Warszawa', 'PROPN', translation: "Warsaw's", lemmaTranslation: 'Warsaw', morph: {'Case': 'Gen', 'Gender': 'Fem'}),
  _MockWord('sięgać', 'VERB', translation: 'dates back', lemmaTranslation: 'to reach, to date back', morph: {'Person': '3', 'Number': 'Sing', 'Tense': 'Pres'}, root: 'sięg-', rootMeaning: 'to reach, to extend to'),
  _MockWord('XIII', 'NUM', translation: '13th', lemmaTranslation: '13th'),
  _MockWord('wiek', 'NOUN', translation: 'century', lemmaTranslation: 'century, age', morph: {'Case': 'Gen', 'Number': 'Sing', 'Gender': 'Masc'}, root: 'wiek-', rootMeaning: 'age, era, century'),
  _MockWord('choć', 'SCONJ', translation: 'although', lemmaTranslation: 'although'),
  _MockWord('prawdziwy', 'ADJ', translation: 'real', lemmaTranslation: 'real, true', morph: {'Case': 'Nom', 'Number': 'Sing', 'Gender': 'Masc'}, root: 'prawd-', rootMeaning: "truth — from 'prawda'"),
  _MockWord('rozkwit', 'NOUN', translation: 'flourishing', lemmaTranslation: 'flourishing, bloom', morph: {'Case': 'Nom', 'Number': 'Sing', 'Gender': 'Masc'}, root: 'kwit-', rootMeaning: "to bloom, to blossom — from 'kwitnąć'"),
  _MockWord('nastąpić', 'VERB', translation: 'occurred', lemmaTranslation: 'to occur, to follow', morph: {'Number': 'Sing', 'Tense': 'Past', 'Gender': 'Masc'}, root: 'stąp-', rootMeaning: "to step, to tread — from 'stąpać'"),
  _MockWord('w', 'ADP', translation: 'in', lemmaTranslation: 'in'),
  _MockWord('XVI', 'NUM', translation: '16th', lemmaTranslation: '16th'),
  _MockWord('i', 'CCONJ', translation: 'and', lemmaTranslation: 'and'),
  _MockWord('XVII', 'NUM', translation: '17th', lemmaTranslation: '17th'),
  _MockWord('stulecie', 'NOUN', translation: 'century', lemmaTranslation: 'century', morph: {'Case': 'Loc', 'Number': 'Sing', 'Gender': 'Neut'}, root: 'sto-', rootMeaning: "hundred — compound with '-lecie' (years)"),
  _MockWord('po', 'ADP', translation: 'After', lemmaTranslation: 'after'),
  _MockWord('zniszczenie', 'NOUN', translation: 'the destruction', lemmaTranslation: 'destruction', morph: {'Case': 'Loc', 'Number': 'Plur', 'Gender': 'Neut'}, root: 'niszcz-', rootMeaning: "to destroy, to ruin — from 'niszczyć'"),
  _MockWord('II', 'NUM', translation: 'Second', lemmaTranslation: 'second'),
  _MockWord('wojna', 'NOUN', translation: 'War', lemmaTranslation: 'war', morph: {'Case': 'Gen', 'Number': 'Sing', 'Gender': 'Fem'}, root: 'wojn-', rootMeaning: 'to fight, to wage war'),
  _MockWord('światowy', 'ADJ', translation: 'World', lemmaTranslation: 'worldwide, global', morph: {'Case': 'Gen', 'Number': 'Sing', 'Gender': 'Fem'}, root: 'świat-', rootMeaning: "world — from 'świat'"),
  _MockWord('miasto', 'NOUN', translation: 'the city', lemmaTranslation: 'city', morph: {'Case': 'Nom', 'Number': 'Sing', 'Gender': 'Neut'}, root: 'miast-', rootMeaning: "place — related to 'miejsce'"),
  _MockWord('zostać', 'AUX', translation: 'was', lemmaTranslation: 'to become, to remain', morph: {'Number': 'Sing', 'Tense': 'Past', 'Gender': 'Neut'}, root: 'sta-', rootMeaning: "to stand — from 'stać'"),
  _MockWord('odbudować', 'VERB', translation: 'rebuilt', lemmaTranslation: 'to rebuild', morph: {'Number': 'Sing', 'Gender': 'Neut', 'Voice': 'Pass'}, root: 'budow-', rootMeaning: "to build — from 'budować'"),
  _MockWord('z', 'ADP', translation: 'with', lemmaTranslation: 'with'),
  _MockWord('niezwykły', 'ADJ', translation: 'extraordinary', lemmaTranslation: 'extraordinary, unusual', morph: {'Case': 'Ins', 'Number': 'Sing', 'Gender': 'Fem'}, root: 'zwykł-', rootMeaning: "usual, ordinary — negated by 'nie-' (not)"),
  _MockWord('staranność', 'NOUN', translation: 'care', lemmaTranslation: 'care, diligence', morph: {'Case': 'Ins', 'Number': 'Sing', 'Gender': 'Fem'}, root: 'staran-', rootMeaning: "to try, to endeavor — from 'starać się'"),
];

const _mockTitles = [
  'Warsaw — Poland\'s Resilient Capital',
  'The Vistula River: Heart of Poland',
  'Old Town: A City Rebuilt from Ashes',
  'Warsaw Through the Centuries',
];

const _promptIdeas = [
  'Cities', 'History', 'Tradition', 'Cuisine', 'Nature',
  'Sport', 'Art', 'Music', 'Cinema', 'Literature',
  'Business', 'Brands', 'Famous people', 'Science', 'Technology', 'Architecture',
];

// ─────────────────────────────────────────────────────────────────────────────

class ReadScreen extends StatefulWidget {
  const ReadScreen({super.key});

  @override
  State<ReadScreen> createState() => _ReadScreenState();
}

class _ReadScreenState extends State<ReadScreen>
    with SingleTickerProviderStateMixin {
  // List state
  final List<Map<String, dynamic>> _texts = [];
  Map<String, dynamic>? _openedText;

  // Generation options
  int _length = 0;
  int _level = 2;
  final TextEditingController _promptCtrl = TextEditingController();

  // Reader state
  String? _tappedWord;
  // Inspect bar display mode: false = the tapped (inflected) form with its
  // in-context gloss, true = the dictionary base form with its lemma gloss.
  bool _inspectBaseForm = false;
  // Single-word inspection: tapping a word highlights it here and (via the
  // sentence alignment data) its gloss in the translation, instead of
  // opening the word sheet right away. A floating bottom panel steps
  // through words and opens the sheet on demand.
  int? _inspectTokenStart; // charStart of the inspected body token
  int? _transHlStart; // highlighted char range in the translation
  int? _transHlEnd;
  // Split view: text on top, translation below, scroll positions mirrored
  // proportionally so both panes show roughly the same fragment.
  bool _splitView = false;
  final ScrollController _bodyScrollCtrl = ScrollController();
  final ScrollController _transScrollCtrl = ScrollController();
  bool _syncingScroll = false;
  // Word-range selection (base text or translation), entered via the
  // "Select" toggle button. A drag/long-press gesture would collide with the
  // existing long-press-to-jump-playback and the page's vertical scroll, so
  // selection here is deliberately mode-based: tap the first word, tap the
  // last word, done — fully discoverable, no gesture-arena guessing.
  bool _selectMode = false;
  int? _selStart;
  int? _selEnd;
  bool _selInTranslation = false;
  bool get _hasSelection => _selStart != null && _selEnd != null;

  // TTS
  final FlutterTts _tts = FlutterTts();
  bool _speaking = false;
  List<String> _speakSentences = [];
  List<int> _speakSentenceStarts = []; // char start of each sentence in body
  int _speakSentenceIdx = -1;
  bool _playbackMode = false;
  // Playback pacing: continuous auto-advance, or pause after every sentence
  // so the learner can repeat/practice before manually moving on.
  bool _stepMode = false;
  // Speech rate cycled by the speed button — applied to _tts.speak() calls.
  // 0.5 is the baseline ("x1") because it's what plays when setSpeechRate is
  // never called at all (the old behavior): flutter_tts's Android plugin maps
  // its 0.0-1.0 range to native rate * 2.0, so dart-value 0.5 == native 1.0
  // (Android's own default/normal rate); on iOS 0.5 is literally
  // AVSpeechUtteranceDefaultSpeechRate. x0.5/x0.25 are that baseline halved
  // again each step, so they read as genuinely half/quarter speed relative
  // to how the app used to sound, not relative to the library's own scale.
  static const List<double> _speechRates = [0.5, 0.25, 0.125];
  static const List<String> _speechRateLabels = ['x1', 'x0.5', 'x0.25'];
  int _speechRateIdx = 0;
  double get _speechRate => _speechRates[_speechRateIdx];
  String get _speechRateLabel => _speechRateLabels[_speechRateIdx];
  // Bumped by _stopEngine/_runPlayback whenever the active playback loop is
  // superseded (pause/skip/stop/dispose). _runPlayback checks this after every
  // awaited speak() call so a stale loop can never keep driving playback forward.
  int _playToken = 0;
  // Word-level highlight (filled by setProgressHandler when platform supports it)
  int? _speakWordStart; // body-absolute start of word being spoken
  int? _speakWordEnd;

  // Selection mode
  bool _selectionMode = false;
  final Set<int> _selectedIndices = {};

  // Language picker state
  Map<String, String>? _activeCourse;
  List<Map<String, String>> _pickerBases = [];
  List<Map<String, String>> _pickerCourses = [];
  String? _pickerSelectedBase;

  final List<String> _lengths = ['Short', 'Medium', 'Long'];
  final List<String> _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  String? get _activeCourseId {
    final c = _activeCourse;
    if (c == null) return null;
    return '${c['baseCode']}_${c['targetCode']}';
  }

  List<Map<String, dynamic>> get _courseTexts {
    final id = _activeCourseId;
    if (id == null) return [];
    return _texts.where((t) => t['courseId'] == id).toList();
  }

  @override
  void initState() {
    super.initState();
    // Makes _tts.speak() resolve exactly when the utterance finishes (instead
    // of immediately), so _runPlayback can auto-advance with a plain await
    // loop instead of a setCompletionHandler callback chain — that chain
    // proved unreliable (playback would stop dead after the first sentence
    // on-device even with awaitSpeakCompletion alone).
    _tts.awaitSpeakCompletion(true);
    // Word-level highlight — progress handler gives offsets within the current
    // sentence string; add the sentence's body-start to get body-absolute positions.
    _tts.setProgressHandler((_, start, end, __) {
      if (!mounted || !_speaking || _speakSentenceIdx < 0) return;
      final sentBase = _speakSentenceIdx < _speakSentenceStarts.length
          ? _speakSentenceStarts[_speakSentenceIdx]
          : 0;
      setState(() {
        _speakWordStart = sentBase + start;
        _speakWordEnd = sentBase + end;
      });
    });
    // Split view: mirror scroll positions both ways, proportionally.
    _bodyScrollCtrl.addListener(
        () => _mirrorScroll(_bodyScrollCtrl, _transScrollCtrl));
    _transScrollCtrl.addListener(
        () => _mirrorScroll(_transScrollCtrl, _bodyScrollCtrl));
    _loadFromStorage();
    // Course selection is global — reload when another tab (e.g. Flashcards)
    // changes it, since IndexedStack keeps this screen's state alive.
    AppStorage.instance.courseChanged.addListener(_reloadActiveCourse);
  }

  /// Keeps the two split-view panes showing the same relative fragment: the
  /// pane being scrolled drives the other to the same fraction of its own
  /// scroll range. The [_syncingScroll] latch stops the mirrored jump from
  /// echoing back as a new scroll event.
  void _mirrorScroll(ScrollController from, ScrollController to) {
    if (!_splitView || _syncingScroll) return;
    if (!from.hasClients || !to.hasClients) return;
    final fromMax = from.position.maxScrollExtent;
    if (fromMax <= 0) return;
    _syncingScroll = true;
    final ratio = (from.offset / fromMax).clamp(0.0, 1.0);
    to.jumpTo(ratio * to.position.maxScrollExtent);
    _syncingScroll = false;
  }

  void _loadFromStorage() {
    _texts.addAll(AppStorage.instance.texts);
    _pickerBases = AppStorage.instance.bases;
    _pickerCourses = AppStorage.instance.courses;
    _pickerSelectedBase = AppStorage.instance.selectedBase;
    _activeCourse = AppStorage.instance.activeCourse;
  }

  void _reloadActiveCourse() {
    if (!mounted) return;
    setState(() {
      _pickerBases = AppStorage.instance.bases;
      _pickerCourses = AppStorage.instance.courses;
      _pickerSelectedBase = AppStorage.instance.selectedBase;
      final newCourse = AppStorage.instance.activeCourse;
      final newId = newCourse == null
          ? null
          : '${newCourse['baseCode']}_${newCourse['targetCode']}';
      _activeCourse = newCourse;
      if (_openedText != null && _openedText!['courseId'] != newId) {
        _openedText = null;
        _tappedWord = null;
        _clearInspection();
      }
    });
  }

  @override
  void dispose() {
    AppStorage.instance.courseChanged.removeListener(_reloadActiveCourse);
    _playToken++;
    _tts.stop();
    _promptCtrl.dispose();
    _bodyScrollCtrl.dispose();
    _transScrollCtrl.dispose();
    super.dispose();
  }

  // ── TTS ─────────────────────────────────────────────────────────────────────

  String _ttsLang(String? code) {
    const map = {
      'pl': 'pl-PL', 'en': 'en-US', 'es': 'es-ES', 'fr': 'fr-FR',
      'de': 'de-DE', 'it': 'it-IT', 'pt': 'pt-PT', 'ru': 'ru-RU',
      'ja': 'ja-JP', 'ko': 'ko-KR', 'zh': 'zh-CN', 'nl': 'nl-NL',
      'sv': 'sv-SE', 'no': 'nb-NO', 'da': 'da-DK', 'fi': 'fi-FI',
    };
    return map[code] ?? 'en-US';
  }

  // Returns (sentences, charStartsInBody) by splitting on sentence boundaries.
  ({List<String> s, List<int> starts}) _parseSentences(String body) {
    final sentences = <String>[];
    final starts = <int>[];
    // [.!?](?=\d) allows dots/etc that are immediately followed by a digit (e.g. "1.000", "3.5")
    final re = RegExp(r'\S(?:[^.!?]|[.!?](?=\d))*(?:[!?]+|\.+(?!\d)|$)');
    for (final m in re.allMatches(body)) {
      final text = m.group(0)!.trimRight();
      if (text.isNotEmpty) {
        sentences.add(text);
        starts.add(m.start);
      }
    }
    if (sentences.isEmpty) {
      sentences.add(body.trim());
      starts.add(0);
    }
    return (s: sentences, starts: starts);
  }

  // ── Token/sentence schema — read side ───────────────────────────────────────
  // Texts generated from now on carry pre-computed tokens/sentences (see the
  // "build side" below); older saved texts and pasted texts (no analysis
  // possible) simply have none, so everything here falls back to the
  // regex-based _parseSentences to keep working for them.

  List<TextToken> _tokensOf(Map<String, dynamic> text) {
    final raw = text['tokens'] as List?;
    if (raw == null) return const [];
    return raw
        .map((e) => TextToken.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<TextSentence> _bodySentencesOf(Map<String, dynamic> text) {
    final raw = text['bodySentences'] as List?;
    if (raw == null) return const [];
    return raw
        .map((e) => TextSentence.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  List<TextSentence> _translationSentencesOf(Map<String, dynamic> text) {
    final raw = text['translationSentences'] as List?;
    if (raw == null) return const [];
    return raw
        .map((e) => TextSentence.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  TextToken? _tokenAt(List<TextToken> tokens, int charStart) {
    for (final t in tokens) {
      if (charStart >= t.charStart && charStart < t.charEnd) return t;
    }
    return null;
  }

  // Same return shape as _parseSentences — a drop-in replacement for it
  // wherever the BODY (target-language) text is being sentence-split, so
  // every playback call site benefits without needing its own branch.
  ({List<String> s, List<int> starts}) _sentencesForBody(String body) {
    final stored =
        _openedText == null ? const <TextSentence>[] : _bodySentencesOf(_openedText!);
    if (stored.isNotEmpty) {
      return (
        s: stored.map((s) => body.substring(s.charStart, s.charEnd)).toList(),
        starts: stored.map((s) => s.charStart).toList(),
      );
    }
    return _parseSentences(body);
  }

  // Like _sentencesForBody but for the translation, plus which body
  // sentence each translation sentence corresponds to — explicit alignment
  // instead of assuming translation and body always have the same sentence
  // count/order (see _speakFromTranslation and _buildTranslationText).
  ({List<String> s, List<int> starts, List<int> alignsToBody}) _translationSentencesFor(
      String translation) {
    final stored = _openedText == null
        ? const <TextSentence>[]
        : _translationSentencesOf(_openedText!);
    if (stored.isNotEmpty) {
      return (
        s: stored.map((s) => translation.substring(s.charStart, s.charEnd)).toList(),
        starts: stored.map((s) => s.charStart).toList(),
        alignsToBody: stored.map((s) => s.alignsToIndex ?? s.index).toList(),
      );
    }
    final parsed = _parseSentences(translation);
    return (
      s: parsed.s,
      starts: parsed.starts,
      alignsToBody: List.generate(parsed.s.length, (i) => i),
    );
  }

  // ── Token/sentence schema — build side (mock) ───────────────────────────────
  // Stands in for what a real AI generation call would return. Kept separate
  // from the read-side helpers above so swapping this for a real API call
  // later doesn't touch any playback/rendering code — it only needs to keep
  // producing the same tokens/bodySentences/translationSentences shape.

  List<TextSentence> _buildMockSentences(String text) {
    final parsed = _parseSentences(text);
    return List.generate(parsed.s.length, (i) {
      final start = parsed.starts[i];
      return TextSentence(index: i, charStart: start, charEnd: start + parsed.s[i].length);
    });
  }

  List<TextToken> _buildMockTokens(
      String text, List<_MockWord> anns, List<TextSentence> sentences) {
    final words = text.split(' ');
    final tokens = <TextToken>[];
    var charPos = 0;
    var sentenceIdx = 0;
    for (var i = 0; i < words.length; i++) {
      final w = words[i];
      final start = charPos;
      final end = start + w.length;
      while (sentenceIdx < sentences.length - 1 && start >= sentences[sentenceIdx].charEnd) {
        sentenceIdx++;
      }
      final ann = anns[i % anns.length];
      tokens.add(TextToken(
        surface: w,
        lemma: ann.lemma,
        translation: ann.translation,
        lemmaTranslation: ann.lemmaTranslation,
        pos: ann.pos,
        morph: ann.morph,
        root: ann.root,
        rootMeaning: ann.rootMeaning,
        sentenceIndex: sentenceIdx,
        charStart: start,
        charEnd: end,
      ));
      charPos = end + 1; // +1 for the joining space
    }
    return tokens;
  }

  // Number of sentences in one copy of the canonical mock paragraph — used
  // to keep sentence indices contiguous across repeated/appended copies.
  int get _mockSentencesPerCopy => _buildMockSentences(_mockPolishText).length;

  // One copy of the canonical mock paragraph's tokens/sentences, shifted by
  // the given offsets so it can be repeated (initial generation) or
  // appended (Continue) without colliding with what's already there.
  ({
    List<TextSentence> bodySentences,
    List<TextSentence> translationSentences,
    List<TextToken> tokens,
  }) _shiftedMockCopy({
    required int bodyOffset,
    required int translationOffset,
    required int sentenceOffset,
  }) {
    final baseBodySentences = _buildMockSentences(_mockPolishText);
    final baseTranslationSentences = _buildMockSentences(_mockEnglishText);
    final baseTokens =
        _buildMockTokens(_mockPolishText, _mockPolishWords, baseBodySentences);

    return (
      bodySentences: baseBodySentences
          .map((s) => TextSentence(
                index: s.index + sentenceOffset,
                charStart: s.charStart + bodyOffset,
                charEnd: s.charEnd + bodyOffset,
              ))
          .toList(),
      translationSentences: baseTranslationSentences
          .map((s) => TextSentence(
                index: s.index + sentenceOffset,
                charStart: s.charStart + translationOffset,
                charEnd: s.charEnd + translationOffset,
                alignsToIndex: s.index + sentenceOffset, // 1:1 in this mock
              ))
          .toList(),
      tokens: baseTokens
          .map((t) => TextToken(
                surface: t.surface,
                lemma: t.lemma,
                translation: t.translation,
                lemmaTranslation: t.lemmaTranslation,
                pos: t.pos,
                morph: t.morph,
                reading: t.reading,
                root: t.root,
                rootMeaning: t.rootMeaning,
                sentenceIndex: t.sentenceIndex + sentenceOffset,
                charStart: t.charStart + bodyOffset,
                charEnd: t.charEnd + bodyOffset,
              ))
          .toList(),
    );
  }

  // Builds `repeats` shifted copies of the canonical mock paragraph, joined
  // exactly like the existing List.filled(...).join(' ') calls so offsets
  // line up with the resulting body/translation strings.
  ({
    String body,
    String translation,
    List<TextToken> tokens,
    List<TextSentence> bodySentences,
    List<TextSentence> translationSentences,
  }) _buildMockAnnotatedText(int repeats) {
    final body = List.filled(repeats, _mockPolishText).join(' ');
    final translation = List.filled(repeats, _mockEnglishText).join(' ');
    final sentencesPerCopy = _mockSentencesPerCopy;

    final tokens = <TextToken>[];
    final bodySentences = <TextSentence>[];
    final translationSentences = <TextSentence>[];
    for (var r = 0; r < repeats; r++) {
      final copy = _shiftedMockCopy(
        bodyOffset: r * (_mockPolishText.length + 1),
        translationOffset: r * (_mockEnglishText.length + 1),
        sentenceOffset: r * sentencesPerCopy,
      );
      bodySentences.addAll(copy.bodySentences);
      translationSentences.addAll(copy.translationSentences);
      tokens.addAll(copy.tokens);
    }

    return (
      body: body,
      translation: translation,
      tokens: tokens,
      bodySentences: bodySentences,
      translationSentences: translationSentences,
    );
  }

  // ── Internal helpers ─────────────────────────────────────────────────────────

  // Stops whatever is currently speaking and invalidates any in-flight
  // _runPlayback loop so it won't advance to another sentence afterward.
  Future<void> _stopEngine() async {
    _playToken++;
    await _tts.stop();
  }

  // Speaks sentences starting at startIdx, auto-advancing as each one
  // finishes, until superseded by pause/skip/stop or the text ends. This
  // await loop *is* the auto-advance mechanism — awaitSpeakCompletion(true)
  // (set in initState) makes _tts.speak() resolve exactly when the utterance
  // ends, so there's no completion-handler callback chain to go stale.
  Future<void> _runPlayback(int startIdx) async {
    _playToken++;
    final token = _playToken;
    await _tts.stop();
    for (int i = startIdx; i < _speakSentences.length; i++) {
      if (token != _playToken || !mounted) return;
      setState(() {
        _speakSentenceIdx = i;
        _speaking = true;
        _speakWordStart = null;
        _speakWordEnd = null;
      });
      await _tts.setSpeechRate(_speechRate);
      await _tts.speak(_speakSentences[i]);
      if (token != _playToken) return; // superseded elsewhere
      if (_stepMode && i + 1 < _speakSentences.length) {
        // Pause after this sentence instead of auto-continuing. Keep the
        // cursor on the sentence just read (don't jump ahead) — the learner
        // uses skip-next to move on when ready, then play to hear it.
        setState(() {
          _speaking = false;
          _speakWordStart = null;
          _speakWordEnd = null;
        });
        return;
      }
    }
    if (mounted) {
      setState(() {
        _speaking = false;
        _speakWordStart = null;
        _speakWordEnd = null;
      });
    }
  }

  // ── Public playback controls ──────────────────────────────────────────────────

  Future<void> _enterPlayback(String body, String? langCode) async {
    await _tts.setLanguage(_ttsLang(langCode));
    final parsed = _sentencesForBody(body);
    if (mounted) setState(() {
      _speakSentences = parsed.s;
      _speakSentenceStarts = parsed.starts;
      _playbackMode = true;
    });
    unawaited(_runPlayback(0));
  }

  Future<void> _pausePlayback() async {
    if (!_speaking) return;
    await _stopEngine();
    if (mounted) setState(() {
      _speaking = false;
      _speakWordStart = null;
      _speakWordEnd = null;
    });
  }

  Future<void> _playCurrent() async {
    if (!_playbackMode || _speakSentenceIdx < 0) return;
    unawaited(_runPlayback(_speakSentenceIdx));
  }

  Future<void> _skipPrev() async {
    if (!_playbackMode) return;
    final idx = _speakSentenceIdx > 0 ? _speakSentenceIdx - 1 : 0;
    if (_speaking) {
      unawaited(_runPlayback(idx));
    } else {
      await _stopEngine();
      if (mounted) setState(() { _speakSentenceIdx = idx; _speakWordStart = null; _speakWordEnd = null; });
    }
  }

  Future<void> _skipNext() async {
    if (!_playbackMode) return;
    final next = _speakSentenceIdx + 1;
    if (next >= _speakSentences.length) return;
    if (_speaking) {
      unawaited(_runPlayback(next));
    } else {
      await _stopEngine();
      if (mounted) setState(() { _speakSentenceIdx = next; _speakWordStart = null; _speakWordEnd = null; });
    }
  }

  // Single word — used by the word-detail sheet.
  Future<void> _speak(String word, String? langCode) async {
    await _tts.setLanguage(_ttsLang(langCode));
    await _tts.setSpeechRate(_speechRate);
    await _tts.speak(word);
  }

  Future<void> _finishPlayback() async {
    await _stopEngine();
    if (mounted) setState(() {
      _speaking = false;
      _playbackMode = false;
      _speakSentenceIdx = -1;
      _speakWordStart = null;
      _speakWordEnd = null;
    });
  }

  // ── Continue text ────────────────────────────────────────────────────────────

  /// Words from the user's flashcards in the given decks, weakest mastery
  /// first, for the AI to weave into generated texts. Mirrors the deck
  /// semantics of the Flashcards screen: General means every course card
  /// and From Texts means text-sourced cards — those two are virtual, so
  /// their ids never appear in a card's own deckIds.
  List<String> _vocabForDecks(Iterable<String> deckIds) {
    final ids = deckIds.toSet();
    if (ids.isEmpty) return const [];
    final cards = AppStorage.instance.flashcards
        .where((c) => c.courseId == _activeCourseId)
        .where((c) =>
            ids.contains(Deck.generalId) ||
            (ids.contains(Deck.fromTextsId) && c.fromTexts) ||
            c.deckIds.any(ids.contains))
        .toList()
      ..sort((a, b) => a.masteryLevel.compareTo(b.masteryLevel));
    return [for (final c in cards.take(15)) c.word];
  }

  // ── Selection mode ──────────────────────────────────────────────────────────

  void _enterSelectionMode(int index) {
    setState(() {
      _selectionMode = true;
      _selectedIndices.add(index);
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) _selectionMode = false;
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIndices.clear();
    });
  }

  void _deleteSelected() {
    final toDelete = _selectedIndices.map((i) => _courseTexts[i]).toList();
    setState(() {
      for (final t in toDelete) {
        _texts.remove(t);
      }
      _selectionMode = false;
      _selectedIndices.clear();
    });
    AppStorage.instance.saveTexts(_texts);
  }

  // ── Language sheet ──────────────────────────────────────────────────────────

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
                    setState(() {
                      _activeCourse = course;
                      final newId = '${course['baseCode']}_${course['targetCode']}';
                      if (_openedText != null && _openedText!['courseId'] != newId) {
                        _openedText = null;
                        _tappedWord = null;
                        _clearInspection();
                      }
                    });
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

  // ── Generate sheet ──────────────────────────────────────────────────────────

  void _showGenerateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        bool generating = false;
        int sheetLength = _length;
        int sheetLevel = _level;
        bool pasteMode = false;
        bool showIdeas = false;
        String? selectedIdea;
        final pasteCtrl = TextEditingController();
        const int pasteMaxChars = 2000;
        // Decks whose vocabulary can be woven into the generated text —
        // General/From Texts plus any custom decks (Alphabet/Babel excluded,
        // they aren't real vocabulary sources).
        final courseId = _activeCourseId;
        final sheetUserDecks = courseId == null
            ? <Deck>[]
            : [
                Deck.general(courseId),
                Deck.fromTexts(courseId),
                ...AppStorage.instance.decks
                    .where((d) => d.courseId == courseId && !d.isVirtual),
              ];
        final Set<String> sheetDeckIds = {};
        return StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
                24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text('New text',
                        style: GoogleFonts.cormorantGaramond(
                            color: AppColors.text,
                            fontSize: 28,
                            fontWeight: FontWeight.w500)),
                    const Spacer(),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ModeTab(
                            label: 'Generate',
                            icon: Icons.auto_awesome_rounded,
                            active: !pasteMode,
                            onTap: () => setSheet(() => pasteMode = false),
                          ),
                          _ModeTab(
                            label: 'Paste',
                            icon: Icons.content_paste_rounded,
                            active: pasteMode,
                            onTap: () => setSheet(() => pasteMode = true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (pasteMode) ...[
                  TextField(
                    controller: pasteCtrl,
                    maxLines: 8,
                    minLines: 4,
                    maxLength: pasteMaxChars,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.dmSans(
                        color: AppColors.text, fontSize: 14, height: 1.5),
                    decoration: InputDecoration(
                      hintText: 'Paste your text here…',
                      hintStyle: GoogleFonts.dmSans(
                          color: AppColors.text3,
                          fontSize: 13,
                          height: 1.5),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Text('PROMPT',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => setSheet(() {
                          showIdeas = !showIdeas;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: showIdeas
                                ? AppColors.primaryGlow
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: showIdeas
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lightbulb_outline_rounded,
                                  size: 13,
                                  color: showIdeas
                                      ? AppColors.primary
                                      : AppColors.text3),
                              const SizedBox(width: 4),
                              Text('Ideas',
                                  style: GoogleFonts.dmSans(
                                      color: showIdeas
                                          ? AppColors.primarySoft
                                          : AppColors.text3,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (showIdeas) ...[
                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: _promptIdeas.map((idea) {
                        final active = selectedIdea == idea;
                        return GestureDetector(
                          onTap: () => setSheet(() {
                            selectedIdea = active ? null : idea;
                            showIdeas = false;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 130),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primaryGlow
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: active ? 1.5 : 1,
                              ),
                            ),
                            child: Text(idea,
                                style: GoogleFonts.dmSans(
                                    color: active
                                        ? AppColors.primarySoft
                                        : AppColors.text,
                                    fontSize: 13,
                                    fontWeight: active
                                        ? FontWeight.w600
                                        : FontWeight.w400)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ] else if (selectedIdea != null) ...[
                    GestureDetector(
                      onTap: () => setSheet(() => selectedIdea = null),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.primary, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_rounded,
                                size: 15, color: AppColors.primary),
                            const SizedBox(width: 8),
                            Text(selectedIdea!,
                                style: GoogleFonts.dmSans(
                                    color: AppColors.primarySoft,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            const Icon(Icons.close_rounded,
                                size: 15, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    TextField(
                      controller: _promptCtrl,
                      maxLines: 3,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.dmSans(
                          color: AppColors.text, fontSize: 14, height: 1.5),
                      decoration: InputDecoration(
                        hintText:
                            'What would you like to read about? Leave empty for a surprise.',
                        hintStyle: GoogleFonts.dmSans(
                            color: AppColors.text3,
                            fontSize: 13,
                            height: 1.5),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Text('LEVEL',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(_levels.length, (i) {
                      final active = sheetLevel == i;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setSheet(() => sheetLevel = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: EdgeInsets.only(right: i < _levels.length - 1 ? 6 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primaryGlow
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: active ? 1.5 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _levels[i],
                              style: GoogleFonts.dmSans(
                                color: active
                                    ? AppColors.primarySoft
                                    : AppColors.text2,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  Text('LENGTH',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 10),
                  Row(
                    children: List.generate(_lengths.length, (i) {
                      final active = sheetLength == i;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setSheet(() => sheetLength = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primaryGlow
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: active ? 1.5 : 1,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _lengths[i],
                              style: GoogleFonts.dmSans(
                                color: active
                                    ? AppColors.primarySoft
                                    : AppColors.text2,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  if (sheetUserDecks.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text('VOCABULARY FROM DECKS',
                            style: GoogleFonts.dmSans(
                                color: AppColors.text3,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2)),
                        const Spacer(),
                        Text(
                          sheetDeckIds.isEmpty
                              ? 'None'
                              : '${sheetDeckIds.length} selected',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Optionally mix in words from your own decks.',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text3, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: sheetUserDecks.map((d) {
                          final sel = sheetDeckIds.contains(d.id);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setSheet(() {
                                if (sel) {
                                  sheetDeckIds.remove(d.id);
                                } else {
                                  sheetDeckIds.add(d.id);
                                }
                              }),
                              child: _SheetChip(
                                  label: d.name,
                                  color: d.accentColor,
                                  selected: sel,
                                  locked: false),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 28),
                GestureDetector(
                  onTap: generating
                      ? null
                      : () async {
                          if (pasteMode) {
                            final text = pasteCtrl.text.trim();
                            if (text.isEmpty) return;
                            setState(() {
                              _texts.insert(0, {
                                'id': 't${DateTime.now().microsecondsSinceEpoch}',
                                'courseId': _activeCourseId ?? '',
                                'title': _mockTitles[
                                    _texts.length % _mockTitles.length],
                                'body': text,
                                'translation': '',
                                'length': '',
                                'level': '',
                                'prompt': '',
                                'deckIds': <String>[],
                              });
                            });
                            AppStorage.instance.saveTexts(_texts);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } else {
                            setSheet(() => generating = true);
                            // Real AI generation through the backend; the
                            // offline mock stays as a fallback so the app
                            // keeps working without a session or network.
                            Map<String, dynamic>? ai;
                            final course = AppStorage.instance.activeCourse;
                            if (ApiClient.instance.hasSession &&
                                course != null) {
                              try {
                                ai = await ApiClient.instance.generateText(
                                  targetLang: course['targetCode'] ?? '',
                                  baseLang: course['baseCode'] ?? '',
                                  level: _levels[sheetLevel],
                                  length: _lengths[sheetLength],
                                  prompt:
                                      selectedIdea ?? _promptCtrl.text.trim(),
                                  hobbies: AppStorage.instance.userHobby,
                                  vocabulary: _vocabForDecks(sheetDeckIds),
                                );
                              } on ApiException {
                                ai = null;
                              }
                            } else {
                              await Future.delayed(
                                  const Duration(milliseconds: 1200));
                            }
                            if (!mounted) return;
                            final multiplier = sheetLength + 1;
                            final annotated = ai == null
                                ? _buildMockAnnotatedText(multiplier)
                                : null;
                            setState(() {
                              _length = sheetLength;
                              _level = sheetLevel;
                              _texts.insert(0, {
                                'id': 't${DateTime.now().microsecondsSinceEpoch}',
                                'courseId': _activeCourseId ?? '',
                                'title': ai?['title'] ??
                                    _mockTitles[
                                        _texts.length % _mockTitles.length],
                                'body': ai?['body'] ?? annotated!.body,
                                'translation': ai?['translation'] ??
                                    annotated!.translation,
                                'length': _lengths[sheetLength],
                                'level': _levels[sheetLevel],
                                'prompt': selectedIdea ?? _promptCtrl.text.trim(),
                                'deckIds': sheetDeckIds.toList(),
                                'tokens': ai?['tokens'] ??
                                    annotated!.tokens
                                        .map((t) => t.toJson())
                                        .toList(),
                                'bodySentences': ai?['bodySentences'] ??
                                    annotated!.bodySentences
                                        .map((s) => s.toJson())
                                        .toList(),
                                'translationSentences':
                                    ai?['translationSentences'] ??
                                        annotated!.translationSentences
                                            .map((s) => s.toJson())
                                            .toList(),
                              });
                            });
                            AppStorage.instance.saveTexts(_texts);
                            if (ctx.mounted) Navigator.pop(ctx);
                          }
                        },
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
                    alignment: Alignment.center,
                    child: generating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                pasteMode
                                    ? Icons.add_rounded
                                    : Icons.auto_awesome_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                pasteMode ? 'Add text' : 'Generate',
                                style: GoogleFonts.dmSans(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Reader actions ──────────────────────────────────────────────────────────

  void _toggleSplitView() {
    setState(() => _splitView = !_splitView);
  }

  // ── Long-press to jump playback ─────────────────────────────────────────────

  // Enters playback mode paused at bodySentenceIdx, highlighting that
  // sentence in both the base text and the translation.
  Future<void> _pauseAtSentence(String body, int sentenceIdx) async {
    await _stopEngine();
    await _tts.setLanguage(_ttsLang(_activeCourse?['targetCode']));
    final parsed = _sentencesForBody(body);
    final idx = sentenceIdx.clamp(0, parsed.s.length - 1);
    if (mounted) setState(() {
      _speakSentences = parsed.s;
      _speakSentenceStarts = parsed.starts;
      _playbackMode = true;
      _speakSentenceIdx = idx;
      _speaking = false;
      _speakWordStart = null;
      _speakWordEnd = null;
    });
  }

  // Called by long-press on a base-text word.
  Future<void> _speakFrom(String body, int wordIndex, List<int> wordStarts) async {
    final parsed = _sentencesForBody(body);
    final charPos = wordStarts[wordIndex];
    int startSentence = 0;
    for (int i = parsed.starts.length - 1; i >= 0; i--) {
      if (charPos >= parsed.starts[i]) { startSentence = i; break; }
    }
    await _pauseAtSentence(body, startSentence);
  }

  // Called by long-press on a translation word — the sentence index is
  // derived from the translation's own sentence boundaries, then mapped to
  // the corresponding body sentence via explicit alignment data when the
  // text has it (see _translationSentencesFor); older/pasted texts fall
  // back to assuming positional 1:1 alignment.
  Future<void> _speakFromTranslation(
      String body, String translation, int wordIndex, List<int> wordStarts) async {
    final parsed = _translationSentencesFor(translation);
    final charPos = wordStarts[wordIndex];
    int startSentence = 0;
    for (int i = parsed.starts.length - 1; i >= 0; i--) {
      if (charPos >= parsed.starts[i]) { startSentence = i; break; }
    }
    final bodySentenceIdx = startSentence < parsed.alignsToBody.length
        ? parsed.alignsToBody[startSentence]
        : startSentence;
    await _pauseAtSentence(body, bodySentenceIdx);
  }

  // ── Word-range selection (tap-based) ────────────────────────────────────────

  void _toggleSelectMode() => setState(() {
        _selectMode = !_selectMode;
        if (!_selectMode) {
          _selStart = null;
          _selEnd = null;
        }
      });

  // First tap in a region (or a tap in the other region) starts a new
  // one-word selection; a second tap in the same region extends it — like
  // click, then shift-click, to pick a range.
  void _onWordSelectTap(int index, bool isTranslation) {
    setState(() {
      if (!_hasSelection || _selInTranslation != isTranslation) {
        _selStart = index;
        _selEnd = index;
        _selInTranslation = isTranslation;
      } else {
        _selEnd = index;
      }
    });
  }

  void _clearSelection() => setState(() {
        _selStart = null;
        _selEnd = null;
      });

  // Selected substring, re-derived from the live body/translation each time
  // rather than cached, so it always matches what's currently on screen.
  String get _selectedText {
    if (!_hasSelection || _openedText == null) return '';
    final source = (_selInTranslation
        ? _openedText!['translation']
        : _openedText!['body']) as String? ?? '';
    final words = source.split(' ');
    final lo = _selStart! <= _selEnd! ? _selStart! : _selEnd!;
    final hi = _selStart! <= _selEnd! ? _selEnd! : _selStart!;
    if (lo < 0 || hi >= words.length) return '';
    return words.sublist(lo, hi + 1).join(' ');
  }

  // De-duplicated (by lemma — base form) tokens covering the current
  // selection, numerals skipped. _selStart/_selEnd are word indices, which
  // line up 1:1 with token indices for the base text, so this is a direct
  // slice — no re-parsing the selected substring. Selections in the
  // translation have no per-token analysis (nothing to look up there yet:
  // it's already in the learner's own language), so they yield nothing.
  List<MapEntry<String, String?>> _selectedWordTranslations() {
    if (!_hasSelection || _selInTranslation || _openedText == null) return [];
    final tokens = _tokensOf(_openedText!);
    if (tokens.isEmpty) return [];
    final lo = _selStart! <= _selEnd! ? _selStart! : _selEnd!;
    final hi = _selStart! <= _selEnd! ? _selEnd! : _selStart!;
    final seen = <String>{};
    final result = <MapEntry<String, String?>>[];
    for (var i = lo; i <= hi && i < tokens.length; i++) {
      final t = tokens[i];
      if (t.pos == 'NUM' || t.pos == 'PUNCT') continue;
      if (!seen.add(t.lemma.toLowerCase())) continue;
      result.add(MapEntry(t.lemma, t.translation));
    }
    return result;
  }

  // Hands the current selection off to Converse: a new conversation opens
  // there in which the AI walks through the sentence and its elements.
  // Only base-text selections carry token analysis (see
  // _selectedWordTranslations above), so the panel disables this for
  // selections made in the translation.
  void _explainSelectionInConverse() {
    final courseId = _activeCourseId;
    final text = _selectedText;
    if (courseId == null || text.isEmpty || _openedText == null) return;

    final tokens = _tokensOf(_openedText!);
    final lo = _selStart! <= _selEnd! ? _selStart! : _selEnd!;
    final hi = _selStart! <= _selEnd! ? _selEnd! : _selStart!;

    // Word indices line up 1:1 with token indices for the base text; rebase
    // each token's char range onto the selection substring so the sentence
    // stays word-tappable inside the chat bubble.
    final selTokens = <TextToken>[];
    if (!_selInTranslation && tokens.isNotEmpty && hi < tokens.length) {
      var pos = 0;
      for (var i = lo; i <= hi; i++) {
        final t = tokens[i];
        selTokens.add(TextToken(
          surface: t.surface,
          lemma: t.lemma,
          translation: t.translation,
          lemmaTranslation: t.lemmaTranslation,
          pos: t.pos,
          morph: t.morph,
          reading: t.reading,
          root: t.root,
          rootMeaning: t.rootMeaning,
          sentenceIndex: 0,
          charStart: pos,
          charEnd: pos + t.surface.length,
        ));
        pos += t.surface.length + 1;
      }
    }

    // When the whole selection sits inside one sentence, pull that
    // sentence's aligned translation along for the walkthrough.
    String? translation;
    if (selTokens.isNotEmpty &&
        tokens[lo].sentenceIndex == tokens[hi].sentenceIndex) {
      final tr = _openedText!['translation'] as String? ?? '';
      if (tr.isNotEmpty) {
        final parts = _translationSentencesFor(tr);
        final j = parts.alignsToBody.indexOf(tokens[lo].sentenceIndex);
        if (j != -1) translation = parts.s[j].trim();
      }
    }

    AppStorage.instance.explainRequest.value = ExplainRequest(
      courseId: courseId,
      text: text,
      translation: translation,
      tokens: selTokens,
    );
    _clearSelection();
  }

  void _showSelectionTranslations() {
    final entries = _selectedWordTranslations();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            Text('Selected words',
                style: GoogleFonts.cormorantGaramond(
                    color: AppColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            if (entries.isEmpty)
              Text('No words in this selection.',
                  style: GoogleFonts.dmSans(
                      color: AppColors.text3, fontSize: 13))
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) =>
                      Container(height: 1, color: AppColors.border),
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(e.key,
                                style: GoogleFonts.dmSans(
                                    color: AppColors.text,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            e.value ?? 'No translation',
                            style: GoogleFonts.dmSans(
                                color: e.value != null
                                    ? AppColors.text2
                                    : AppColors.text3,
                                fontSize: 14,
                                fontStyle: e.value != null
                                    ? FontStyle.normal
                                    : FontStyle.italic),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Maps a Universal Dependencies POS tag to a learner-facing label.
  String _posLabel(String pos) => switch (pos) {
        'NOUN' => 'noun',
        'PROPN' => 'proper noun',
        'VERB' || 'AUX' => 'verb',
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

  void _onWordTap(TextToken token) {
    if (token.translation == null) return;
    setState(() {
      if (_inspectTokenStart == token.charStart) {
        _clearInspection();
      } else {
        _inspectToken(token);
      }
    });
  }

  void _inspectToken(TextToken token) {
    _inspectTokenStart = token.charStart;
    final range = _translationHighlightFor(token);
    _transHlStart = range?.$1;
    _transHlEnd = range?.$2;
  }

  void _clearInspection() {
    _inspectTokenStart = null;
    _transHlStart = null;
    _transHlEnd = null;
  }

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

  bool _isWordChar(String s, int index) =>
      index >= 0 && index < s.length && _letterOrDigit.hasMatch(s[index]);

  /// Index of the [n]-th whole-word occurrence of [needle] in [haystack]
  /// (both already lowercased), or -1. Word boundaries stop "and" from
  /// matching inside "band".
  int _nthWordMatch(String haystack, String needle, int n) {
    var from = 0, count = 0;
    while (true) {
      final idx = haystack.indexOf(needle, from);
      if (idx < 0) return -1;
      final boundaryOk = !_isWordChar(haystack, idx - 1) &&
          !_isWordChar(haystack, idx + needle.length);
      if (boundaryOk) {
        if (count == n) return idx;
        count++;
      }
      from = idx + 1;
    }
  }

  /// Char range to highlight in the translation for [token]: its gloss
  /// located inside the aligned translation sentence, otherwise the whole
  /// aligned sentence. Repeated words ("i ... i" -> "and ... and") map to
  /// the matching occurrence, not always the first one: the token's
  /// occurrence number among same-glossed tokens of its sentence picks the
  /// same-numbered occurrence of the gloss in the translation.
  (int, int)? _translationHighlightFor(TextToken token) {
    final text = _openedText;
    if (text == null) return null;
    final translation = (text['translation'] as String?) ?? '';
    if (translation.isEmpty) return null;
    TextSentence? sent;
    for (final s in _translationSentencesOf(text)) {
      if ((s.alignsToIndex ?? s.index) == token.sentenceIndex) {
        sent = s;
        break;
      }
    }
    if (sent == null) return null;
    final segStart = sent.charStart.clamp(0, translation.length);
    final segEnd = sent.charEnd.clamp(segStart, translation.length);
    final gloss = splitTrailingPunct((token.translation ?? '').trim())
        .core
        .toLowerCase();
    if (gloss.isNotEmpty) {
      var occurrence = 0;
      for (final t in _tokensOf(text)) {
        if (t.sentenceIndex != token.sentenceIndex) continue;
        if (t.charStart >= token.charStart) break;
        final other = splitTrailingPunct((t.translation ?? '').trim())
            .core
            .toLowerCase();
        if (other == gloss) occurrence++;
      }
      final segment = translation.substring(segStart, segEnd).toLowerCase();
      var idx = _nthWordMatch(segment, gloss, occurrence);
      // More repeats in the body than in the translation — reuse the first.
      if (idx < 0 && occurrence > 0) idx = _nthWordMatch(segment, gloss, 0);
      if (idx >= 0) return (segStart + idx, segStart + idx + gloss.length);
    }
    return (segStart, segEnd);
  }

  /// One-tap add from the inspect bar: creates the flashcard right away
  /// (General deck); if the word already has a card, offers extending it to
  /// more decks — same rules as the word sheet's add flow.
  void _quickAddToFlashcards(TextToken token) {
    final courseId = _activeCourseId;
    if (courseId == null || token.translation == null) return;
    final storage = AppStorage.instance;
    final existing = storage.flashcards;
    final word = token.lemma;
    Flashcard? existingCard;
    for (final c in existing) {
      if (c.courseId == courseId && c.word == word) {
        existingCard = c;
        break;
      }
    }
    if (existingCard != null) {
      final userDecks = AppStorage.instance.decks
          .where((d) => d.courseId == courseId && !d.isVirtual)
          .toList();
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _ExtendDecksSheet(
          card: existingCard!,
          userDecks: userDecks,
        ),
      ).then((addedCount) {
        if (addedCount is int && addedCount > 0) {
          storage.saveFlashcards(existing);
          storage.flashcardsChanged.value++;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(_flashcardSnack(
              '"$word" added to $addedCount more deck${addedCount == 1 ? '' : 's'}'));
        }
      });
      return;
    }
    final card = Flashcard(
      id: '${DateTime.now().millisecondsSinceEpoch}',
      word: word,
      translation: token.lemmaTranslation ?? token.translation!,
      wordType: _posLabel(token.pos),
      courseId: courseId,
      fromTexts: true,
      morph: (token.pos == 'NOUN' || token.pos == 'PROPN') &&
              token.morph.containsKey('Gender')
          ? {'Gender': token.morph['Gender']!}
          : null,
      root: token.root,
      rootMeaning: token.rootMeaning,
    );
    storage.saveFlashcards([...existing, card]);
    storage.flashcardsChanged.value++;
    ScaffoldMessenger.of(context)
        .showSnackBar(_flashcardSnack('"$word" added to flashcards'));
  }

  /// Word tokens the inspect arrows step through, in text order.
  List<TextToken> _navigableTokens() {
    final text = _openedText;
    if (text == null) return const [];
    return [
      for (final t in _tokensOf(text))
        if (t.pos != 'PUNCT' && t.translation != null) t,
    ];
  }

  void _inspectStep(int direction) {
    final tokens = _navigableTokens();
    if (tokens.isEmpty) return;
    final current =
        tokens.indexWhere((t) => t.charStart == _inspectTokenStart);
    final next = (current + direction).clamp(0, tokens.length - 1);
    setState(() => _inspectToken(tokens[next]));
  }

  TextToken? _inspectedToken() {
    final text = _openedText;
    if (text == null || _inspectTokenStart == null) return null;
    for (final t in _tokensOf(text)) {
      if (t.charStart == _inspectTokenStart) return t;
    }
    return null;
  }

  void _showWordSheet(TextToken token) {
    final courseId = _activeCourseId;
    final userDecks = courseId == null
        ? <Deck>[]
        : AppStorage.instance.decks
            .where((d) => d.courseId == courseId && !d.isVirtual)
            .toList();
    // Flashcards store the dictionary form, not whatever inflected form was
    // tapped — that's the useful thing to drill with spaced repetition.
    final flashcardWord = token.lemma;
    final flashcardTranslation = token.lemmaTranslation ?? token.translation!;
    final wordType = _posLabel(token.pos);
    // token.morph describes THIS occurrence (e.g. Case=Ins for "stolicą") —
    // most of that is agreement/inflection, not true of the dictionary form
    // the flashcard stores. Gender is the one feature that's genuinely
    // lexical for a noun (it doesn't change), so that's the only one carried
    // over; everything else would misleadingly claim the lemma has a case.
    final flashcardMorph = (token.pos == 'NOUN' || token.pos == 'PROPN') &&
            token.morph.containsKey('Gender')
        ? {'Gender': token.morph['Gender']!}
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _WordSheet(
        token: token,
        wordType: wordType,
        userDecks: userDecks,
        courseId: courseId,
        onSpeakSurface: () =>
            _speak(splitTrailingPunct(token.surface).core, _activeCourse?['targetCode']),
        onSpeakLemma: () => _speak(token.lemma, _activeCourse?['targetCode']),
        onAddToFlashcards: (selectedDeckIds) {
          Navigator.pop(context);
          if (courseId == null) {
            ScaffoldMessenger.of(context).showSnackBar(_flashcardSnack(
                'Select a course first'));
            return;
          }
          final storage = AppStorage.instance;
          final existing = storage.flashcards;
          Flashcard? existingCard;
          for (final c in existing) {
            if (c.courseId == courseId && c.word == flashcardWord) {
              existingCard = c;
              break;
            }
          }
          if (existingCard != null) {
            // Already have this word — offer to extend it to more decks
            // instead of silently rejecting or creating a duplicate.
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              isScrollControlled: true,
              builder: (_) => _ExtendDecksSheet(
                card: existingCard!,
                userDecks: userDecks,
              ),
            ).then((addedCount) {
              if (addedCount is int && addedCount > 0) {
                storage.saveFlashcards(existing);
                storage.flashcardsChanged.value++;
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(_flashcardSnack(
                    '"$flashcardWord" added to $addedCount more deck${addedCount == 1 ? '' : 's'}'));
              }
            });
            return;
          }
          final card = Flashcard(
            id: '${DateTime.now().millisecondsSinceEpoch}',
            word: flashcardWord,
            translation: flashcardTranslation,
            wordType: wordType,
            courseId: courseId,
            fromTexts: true,
            deckIds: selectedDeckIds,
            morph: flashcardMorph,
            root: token.root,
            rootMeaning: token.rootMeaning,
          );
          storage.saveFlashcards([...existing, card]);
          storage.flashcardsChanged.value++;
          ScaffoldMessenger.of(context)
              .showSnackBar(_flashcardSnack('"$flashcardWord" added to flashcards'));
        },
      ),
    ).whenComplete(() => setState(() => _tappedWord = null));
  }

  SnackBar _flashcardSnack(String message) => SnackBar(
        content: Text(message,
            style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 13)),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      );

  void _openText(Map<String, dynamic> text) {
    setState(() {
      _openedText = text;
      _tappedWord = null;
      _clearInspection();
      _selectMode = false;
      _selStart = null;
      _selEnd = null;
    });
  }

  // Word-by-word, mirroring the base text — lets long-press jump playback to
  // the tapped sentence (see _speakFromTranslation) and highlights the
  // sentence currently being spoken.
  Widget _buildTranslationText(String body, String translation) {
    if (translation.isEmpty) return const SizedBox.shrink();
    final words = translation.split(' ');
    final wordStarts = <int>[];
    var charPos = 0;
    for (final w in words) {
      wordStarts.add(charPos);
      charPos += w.length + 1;
    }
    final parsed = _translationSentencesFor(translation);
    // Map the body sentence currently playing back to ITS translation
    // sentence via explicit alignment, rather than assuming they share an
    // index — a translation can legitimately merge/split sentences.
    final highlightIdx = _playbackMode && _speakSentenceIdx >= 0
        ? parsed.alignsToBody.indexOf(_speakSentenceIdx)
        : -1;
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: List.generate(words.length, (i) {
        final word = words[i];
        final isSpeaking = highlightIdx >= 0 &&
            highlightIdx < parsed.starts.length &&
            wordStarts[i] >= parsed.starts[highlightIdx] &&
            wordStarts[i] <
                (highlightIdx + 1 < parsed.starts.length
                    ? parsed.starts[highlightIdx + 1]
                    : translation.length);
        final isSelected = _hasSelection &&
            _selInTranslation &&
            i >= (_selStart! <= _selEnd! ? _selStart! : _selEnd!) &&
            i <= (_selStart! <= _selEnd! ? _selEnd! : _selStart!);
        // Mirror of the inspected body word: its gloss (or, when the gloss
        // can't be located verbatim, the whole aligned sentence).
        final isInspected = _transHlStart != null &&
            wordStarts[i] < _transHlEnd! &&
            wordStarts[i] + word.length > _transHlStart!;
        return GestureDetector(
          onTap:
              _selectMode ? () => _onWordSelectTap(i, true) : null,
          onLongPress: _selectMode
              ? null
              : () => _speakFromTranslation(body, translation, i, wordStarts),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : isInspected
                      ? AppColors.primaryGlow
                      : isSpeaking
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              word,
              style: GoogleFonts.dmSans(
                color: isInspected
                    ? AppColors.primarySoft
                    : isSpeaking
                        ? AppColors.primary
                        : AppColors.text2,
                fontSize: 15,
                height: 1.75,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        );
      }),
    );
  }

  void _closeReader() {
    _playToken++;
    _tts.stop();
    setState(() {
      _openedText = null;
      _tappedWord = null;
      _clearInspection();
      _selectMode = false;
      _selStart = null;
      _selEnd = null;
      _speaking = false;
      _playbackMode = false;
      _speakSentenceIdx = -1;
      _speakWordStart = null;
      _speakWordEnd = null;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _openedText != null
            ? _buildReaderView(_openedText!)
            : _buildListView(),
      ),
    );
  }

  // ── List view ───────────────────────────────────────────────────────────────

  Widget _buildListView() {
    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildListHeader(),
            Expanded(
              child: _activeCourse == null
                  ? _buildNoCourseState()
                  : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                children: [
                  if (!_selectionMode) _buildAddTextTile(),
                  if (_courseTexts.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text('RECENT',
                        style: GoogleFonts.dmSans(
                            color: AppColors.text3,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2)),
                    const SizedBox(height: 12),
                    ...List.generate(
                      _courseTexts.length,
                      (i) => _buildTextListItem(i, _courseTexts[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        // Trash FAB
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          bottom: _selectionMode && _selectedIndices.isNotEmpty ? 32 : -100,
          right: 24,
          child: GestureDetector(
            onTap: _deleteSelected,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B6B).withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.delete_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListHeader() {
    if (_selectionMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Row(
          children: [
            Text(
              _selectedIndices.isEmpty
                  ? 'Select items'
                  : '${_selectedIndices.length} selected',
              style: GoogleFonts.dmSans(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _exitSelectionMode,
              child: Text('Cancel',
                  style: GoogleFonts.dmSans(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
    }

    return Padding(
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
                        spreadRadius: 1),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          CourseBadge(
            course: _activeCourse,
            onTap: _showLanguageSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildNoCourseState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.language_rounded,
                color: AppColors.text3, size: 40),
            const SizedBox(height: 16),
            Text(
              'No course selected',
              style: GoogleFonts.dmSans(
                  color: AppColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the language button above to choose a course.',
              style: GoogleFonts.dmSans(
                  color: AppColors.text3, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTextTile() {
    return GestureDetector(
      onTap: _showGenerateSheet,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryGlow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('New text',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Tap to choose type and level',
                      style: GoogleFonts.dmSans(
                          color: AppColors.text2, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.add_rounded, color: AppColors.text3, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextListItem(int index, Map<String, dynamic> text) {
    final isSelected = _selectedIndices.contains(index);

    return GestureDetector(
      onTap: _selectionMode ? () => _toggleSelection(index) : () => _openText(text),
      onLongPress: _selectionMode ? null : () => _enterSelectionMode(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryGlow
              : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Selection circle
            if (_selectionMode) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.text3,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text['title'] as String,
                    style: GoogleFonts.dmSans(
                        color: isSelected ? AppColors.primarySoft : AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGlow,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                            (text['level'] as String?) ?? 'B1',
                            style: GoogleFonts.dmSans(
                                color: AppColors.primarySoft,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                            (text['length'] as String?) ?? 'Short',
                            style: GoogleFonts.dmSans(
                                color: AppColors.text2,
                                fontSize: 10,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!_selectionMode) ...[
              const SizedBox(width: 12),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.text3, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  // ── Reader view ─────────────────────────────────────────────────────────────

  Widget _buildReaderView(Map<String, dynamic> text) {
    final body = text['body'] as String;
    final words = body.split(' ');

    // Pre-compute char start of each word in body for TTS highlighting
    final wordStarts = <int>[];
    var _charPos = 0;
    for (final w in words) {
      wordStarts.add(_charPos);
      _charPos += w.length + 1;
    }

    return Stack(
      children: [
        _buildReaderColumn(text, body, words, wordStarts),
        // Floating selection panel — appears bottom-left whenever a word
        // range is selected (base text or translation), offering a Converse
        // walkthrough of the selection plus a translations list.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          bottom: _hasSelection ? 24 : -100,
          left: 20,
          child: _buildSelectionPanel(),
        ),
      ],
    );
  }

  Widget _inspectBarButton(IconData icon, VoidCallback? onTap,
      {bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryGlow : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: active ? AppColors.primary : AppColors.border),
        ),
        child: Icon(icon,
            size: 24,
            color: active
                ? AppColors.primary
                : onTap == null
                    ? AppColors.text3
                    : AppColors.text),
      ),
    );
  }

  /// Docked bottom bar shown while a word is inspected: prev/next arrows,
  /// the word's gloss in the middle (tap it — or the book button — for the
  /// full word sheet with add-to-flashcards). A solid bar instead of a
  /// floating overlay, so mis-taps can't land on the text underneath.
  Widget _buildInspectBar() {
    final token = _inspectedToken();
    if (token == null) return const SizedBox.shrink();
    // Base-form mode (toggled in the top bar) shows the dictionary form and
    // its lemma gloss instead of the tapped inflected form.
    final headline = _inspectBaseForm
        ? token.lemma
        : splitTrailingPunct(token.surface).core;
    final glossSource = _inspectBaseForm
        ? (token.lemmaTranslation ?? token.translation)
        : token.translation;
    final gloss = splitTrailingPunct((glossSource ?? '').trim()).core;
    void openSheet() {
      setState(() => _tappedWord = token.surface);
      _showWordSheet(token);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _inspectBarButton(Icons.chevron_left_rounded,
              () => _inspectStep(-1)),
          const SizedBox(width: 10),
          // Inline translation — no sheet needed for a quick check.
          Expanded(
            child: GestureDetector(
              onTap: openSheet,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
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
          // Full word sheet: details + deck-aware add to flashcards.
          _inspectBarButton(Icons.menu_book_rounded, openSheet),
          const SizedBox(width: 10),
          // One-tap add to flashcards.
          _inspectBarButton(
              Icons.style_rounded, () => _quickAddToFlashcards(token)),
          const SizedBox(width: 10),
          _inspectBarButton(Icons.chevron_right_rounded,
              () => _inspectStep(1)),
        ],
      ),
    );
  }

  Widget _buildReaderColumn(Map<String, dynamic> text, String body,
      List<String> words, List<int> wordStarts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reader header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              GestureDetector(
                onTap: _closeReader,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Icon(Icons.arrow_back_rounded,
                      color: AppColors.text2, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text['title'] as String,
                  style: GoogleFonts.dmSans(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                    (text['level'] as String?) ?? 'B1',
                    style: GoogleFonts.dmSans(
                        color: AppColors.primarySoft,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                    (text['length'] as String?) ?? 'Short',
                    style: GoogleFonts.dmSans(
                        color: AppColors.text2,
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
        // Action bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              // Listen button — always visible; highlights while playback is
              // active and tapping it again stops playback (skip/prev/pause
              // and the pacing toggle live in the floating panel below the
              // content instead).
              GestureDetector(
                onTap: _playbackMode
                    ? _finishPlayback
                    : () => _enterPlayback(body, _activeCourse?['targetCode']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _playbackMode ? AppColors.primaryGlow : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _playbackMode ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _playbackMode ? Icons.stop_rounded : Icons.volume_up_rounded,
                        size: 15,
                        color: _playbackMode ? AppColors.primary : AppColors.text2,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _playbackMode ? 'Stop' : 'Listen',
                        style: GoogleFonts.dmSans(
                          color: _playbackMode ? AppColors.primary : AppColors.text2,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Speech rate — tap cycles x1 → x0.5 → x0.25 → x1.
              Tooltip(
                message: 'Reading speed: $_speechRateLabel',
                child: GestureDetector(
                  onTap: () => setState(() =>
                      _speechRateIdx = (_speechRateIdx + 1) % _speechRates.length),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.speed_rounded,
                            size: 14, color: AppColors.text2),
                        const SizedBox(width: 4),
                        Text(
                          _speechRateLabel,
                          style: GoogleFonts.dmSans(
                            color: AppColors.text2,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Select mode — while on, tapping words picks a range instead
              // of opening the translation sheet or jumping playback.
              Tooltip(
                message: _selectMode
                    ? 'Exit selection mode'
                    : 'Select words to translate or discuss',
                child: GestureDetector(
                  onTap: _toggleSelectMode,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _selectMode ? AppColors.primaryGlow : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _selectMode ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Icon(
                      Icons.highlight_alt_rounded,
                      size: 16,
                      color: _selectMode ? AppColors.primary : AppColors.text2,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // Translation — opens the split view (text top, translation
              // bottom, synced scrolling).
              Tooltip(
                message: _splitView
                    ? 'Hide translation'
                    : 'Show translation (split view)',
                child: GestureDetector(
                  onTap: _toggleSplitView,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _splitView
                          ? AppColors.primaryGlow
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            _splitView ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: Icon(Icons.translate_rounded,
                        color:
                            _splitView ? AppColors.primary : AppColors.text2,
                        size: 16),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Word-bar display mode: base (dictionary) form instead of
              // the tapped inflected form.
              Tooltip(
                message: _inspectBaseForm
                    ? 'Word bar: showing base form'
                    : 'Word bar: show base form',
                child: GestureDetector(
                  onTap: () => setState(
                      () => _inspectBaseForm = !_inspectBaseForm),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: _inspectBaseForm
                          ? AppColors.primaryGlow
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _inspectBaseForm
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Icon(
                      Icons.spellcheck_rounded,
                      size: 16,
                      color: _inspectBaseForm
                          ? AppColors.primary
                          : AppColors.text2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Text content — plain reader, or split view (text top /
        // translation bottom, scroll positions mirrored).
        Expanded(
          child: _splitView &&
                  ((text['translation'] as String?) ?? '').isNotEmpty
              ? _buildSplitView(text, body, words, wordStarts)
              : SingleChildScrollView(
            controller: _bodyScrollCtrl,
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, _hasSelection ? 110 : 32),
            child: _buildBodyWrap(text, body, words, wordStarts),
          ),
        ),
        if (_playbackMode)
          _buildPlaybackBar()
        else if (_inspectTokenStart != null && !_hasSelection)
          _buildInspectBar(),
      ],
    );
  }

  /// Docked playback bar — same style as the inspect bar: pacing toggle,
  /// skip prev, play/pause, skip next.
  Widget _buildPlaybackBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Tooltip(
            message: _stepMode
                ? 'Step mode: pauses after every sentence'
                : 'Auto mode: reads straight through',
            child: _inspectBarButton(
              _stepMode
                  ? Icons.pause_circle_outline_rounded
                  : Icons.fast_forward_rounded,
              () => setState(() => _stepMode = !_stepMode),
              active: _stepMode,
            ),
          ),
          _inspectBarButton(Icons.skip_previous_rounded, _skipPrev),
          _inspectBarButton(
            _speaking ? Icons.pause_rounded : Icons.play_arrow_rounded,
            _speaking ? _pausePlayback : _playCurrent,
          ),
          _inspectBarButton(Icons.skip_next_rounded, _skipNext),
        ],
      ),
    );
  }

  /// Split view: text pane on top, translation pane below, scroll
  /// positions mirrored so both show the same relative fragment.
  Widget _buildSplitView(Map<String, dynamic> text, String body,
      List<String> words, List<int> wordStarts) {
    final bottomPad = _hasSelection ? 110.0 : 24.0;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _bodyScrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: _buildBodyWrap(text, body, words, wordStarts),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          height: 1,
          color: AppColors.border,
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _transScrollCtrl,
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPad),
            child:
                _buildTranslationText(body, text['translation'] as String),
          ),
        ),
      ],
    );
  }

  /// The reading text as a tappable word cloud — used by both the normal
  /// reader and the split view's top pane.
  Widget _buildBodyWrap(Map<String, dynamic> text, String body,
      List<String> words, List<int> wordStarts) {
    final tokens = _tokensOf(text);
    return Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: List.generate(words.length, (i) {
                    final word = words[i];
                    final split = splitTrailingPunct(word);
                    final token = tokens.isEmpty ? null : _tokenAt(tokens, wordStarts[i]);
                    final hasTranslation = token?.translation != null;
                    final isTapped = token != null &&
                        (_tappedWord == token.surface ||
                            _inspectTokenStart == token.charStart);
                    final isSelected = _hasSelection &&
                        !_selInTranslation &&
                        i >= (_selStart! <= _selEnd! ? _selStart! : _selEnd!) &&
                        i <= (_selStart! <= _selEnd! ? _selEnd! : _selStart!);
                    // Word-level (setProgressHandler fired) takes priority;
                    // fall back to sentence-level when platform doesn't support it.
                    final bool isSpeaking;
                    if (_speakWordStart != null && _speakWordEnd != null) {
                      isSpeaking = wordStarts[i] >= _speakWordStart! &&
                          wordStarts[i] < _speakWordEnd!;
                    } else {
                      isSpeaking = _speakSentenceIdx >= 0 &&
                          _speakSentenceIdx < _speakSentenceStarts.length &&
                          wordStarts[i] >=
                              _speakSentenceStarts[_speakSentenceIdx] &&
                          wordStarts[i] <
                              _speakSentenceStarts[_speakSentenceIdx] +
                                  _speakSentences[_speakSentenceIdx].length;
                    }
                    return GestureDetector(
                      onTap: _selectMode
                          ? () => _onWordSelectTap(i, false)
                          : hasTranslation
                              ? () => _onWordTap(token!)
                              : null,
                      onLongPress: _selectMode
                          ? null
                          : () => _speakFrom(body, i, wordStarts),
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
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : isTapped
                                      ? AppColors.primaryGlow
                                      : isSpeaking
                                          ? AppColors.primary
                                              .withValues(alpha: 0.18)
                                          : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              split.core,
                              style: GoogleFonts.dmSans(
                                color: isTapped
                                    ? AppColors.primarySoft
                                    : isSpeaking
                                        ? AppColors.primary
                                        : AppColors.text,
                                fontSize: 17,
                                height: 1.8,
                                fontWeight: FontWeight.w400,
                                decoration: hasTranslation
                                    ? TextDecoration.underline
                                    : TextDecoration.none,
                                decorationColor:
                                    AppColors.primary.withValues(alpha: 0.4),
                                decorationStyle: TextDecorationStyle.dotted,
                              ),
                            ),
                          ),
                          if (split.trail.isNotEmpty)
                            Text(
                              split.trail,
                              style: GoogleFonts.dmSans(
                                color: AppColors.text,
                                fontSize: 17,
                                height: 1.8,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
    );
  }

  // Floating panel shown while a word range is selected (base text or
  // translation): discuss the selection in Converse (base text only — the
  // translation has no token analysis to discuss), list translations for
  // its words (numbers skipped), or dismiss the selection.
  Widget _buildSelectionPanel() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PlayCtrlBtn(
            icon: Icons.forum_rounded,
            active: !_selInTranslation,
            onTap: _selInTranslation ? null : _explainSelectionInConverse,
          ),
          _panelDivider(),
          _PlayCtrlBtn(
            icon: Icons.translate_rounded,
            active: true,
            onTap: _showSelectionTranslations,
          ),
          _panelDivider(),
          _PlayCtrlBtn(
            icon: Icons.close_rounded,
            active: true,
            onTap: _clearSelection,
          ),
        ],
      ),
    );
  }

  Widget _panelDivider() => Container(
        width: 1,
        height: 24,
        color: AppColors.border,
      );
}

// ── Word sheet ────────────────────────────────────────────────────────────────

class _WordSheet extends StatefulWidget {
  final TextToken token;
  final String wordType;
  final List<Deck> userDecks;
  final String? courseId;
  final void Function(Set<String> selectedDeckIds) onAddToFlashcards;
  final VoidCallback? onSpeakSurface;
  final VoidCallback? onSpeakLemma;

  const _WordSheet({
    required this.token,
    required this.wordType,
    required this.userDecks,
    this.courseId,
    required this.onAddToFlashcards,
    this.onSpeakSurface,
    this.onSpeakLemma,
  });

  @override
  State<_WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<_WordSheet> {
  final Set<String> _selectedDeckIds = {};
  late List<Deck> _decks;

  @override
  void initState() {
    super.initState();
    _decks = List.from(widget.userDecks);
  }

  Future<void> _createDeck() async {
    final courseId = widget.courseId;
    if (courseId == null) return;
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
    final taken = const ['general', 'from texts', 'babel']
            .contains(name.trim().toLowerCase()) ||
        AppStorage.instance.decks.any((d) =>
            d.courseId == courseId &&
            d.name.trim().toLowerCase() == name.trim().toLowerCase());
    if (taken) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('A deck named "$name" already exists',
            style: GoogleFonts.dmSans(color: AppColors.text, fontSize: 13)),
        backgroundColor: AppColors.card,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final deck = Deck(
        id: '${DateTime.now().millisecondsSinceEpoch}', name: name, courseId: courseId);
    await AppStorage.instance.saveDecks([...AppStorage.instance.decks, deck]);
    setState(() {
      _decks.add(deck);
      _selectedDeckIds.add(deck.id);
    });
  }

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
    final token = widget.token;
    final showDeckSection = _decks.isNotEmpty || widget.courseId != null;
    // Strip trailing sentence punctuation for display — the sheet shows the
    // word itself, not "word." with a period stuck to it (token.surface
    // keeps the punctuation attached since that's still one tap target).
    final displayWord = splitTrailingPunct(token.surface).core;
    // Same deal for the translation gloss — a word at the end of a
    // sentence can carry a trailing period/comma if it was authored (or,
    // later, AI-generated) as a fragment of the full sentence translation.
    final displayTranslation = splitTrailingPunct(token.translation ?? '').core;
    // Only show a "base form" section when it actually differs from what
    // was tapped — otherwise it's the same word/translation twice.
    final hasBaseForm = token.lemma != displayWord;
    final hasRoot = token.root != null && token.root!.isNotEmpty;

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
                    // The word as tapped, exactly as it appears in the text.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(displayWord,
                              style: GoogleFonts.cormorantGaramond(
                                  color: AppColors.text,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w400,
                                  height: 1.0)),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onSpeakSurface,
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
                    Text(widget.wordType,
                        style: GoogleFonts.dmSans(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5)),
                    // Attributes — case, gender, tense, etc. (empty for
                    // words/languages that don't have them).
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
                    // Translation of this exact (inflected) form.
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
                              onTap: widget.onSpeakLemma,
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
                    // Deck selection
                    if (showDeckSection) ...[
                      const SizedBox(height: 18),
                      _sectionLabel('ADD TO DECK'),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Locked virtual decks
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: _SheetChip(
                                  label: 'General',
                                  color: Color(0xFF7C5CFC),
                                  selected: true,
                                  locked: true),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: _SheetChip(
                                  label: 'From Texts',
                                  color: Color(0xFF26C6DA),
                                  selected: true,
                                  locked: true),
                            ),
                            // User decks — toggleable
                            ..._decks.map((d) {
                              final sel = _selectedDeckIds.contains(d.id);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    if (sel) {
                                      _selectedDeckIds.remove(d.id);
                                    } else {
                                      _selectedDeckIds.add(d.id);
                                    }
                                  }),
                                  child: _SheetChip(
                                      label: d.name,
                                      color: d.accentColor,
                                      selected: sel,
                                      locked: false),
                                ),
                              );
                            }),
                            if (widget.courseId != null)
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
                      ),
                    ],
                    const SizedBox(height: 20),
                    // Add button
                    GestureDetector(
                      onTap: () => widget.onAddToFlashcards(_selectedDeckIds),
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

class _ExtendDecksSheet extends StatefulWidget {
  final Flashcard card;
  final List<Deck> userDecks;

  const _ExtendDecksSheet({required this.card, required this.userDecks});

  @override
  State<_ExtendDecksSheet> createState() => _ExtendDecksSheetState();
}

class _ExtendDecksSheetState extends State<_ExtendDecksSheet> {
  final Set<String> _selectedDeckIds = {};

  @override
  Widget build(BuildContext context) {
    final currentDeckNames = widget.userDecks
        .where((d) => widget.card.deckIds.contains(d.id))
        .map((d) => d.name)
        .toList();
    final availableDecks = widget.userDecks
        .where((d) => !widget.card.deckIds.contains(d.id))
        .toList();
    final message = currentDeckNames.isEmpty
        ? '"${widget.card.word}" is already in your flashcards.'
        : '"${widget.card.word}" is already in: ${currentDeckNames.join(', ')}.';

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                    Text('Already in your flashcards',
                        style: GoogleFonts.cormorantGaramond(
                            color: AppColors.text,
                            fontSize: 28,
                            fontWeight: FontWeight.w500,
                            height: 1.1)),
                    const SizedBox(height: 12),
                    Text(message,
                        style: GoogleFonts.dmSans(
                            color: AppColors.text2, fontSize: 14, height: 1.4)),
                    if (availableDecks.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Text('You can add it to more decks:',
                          style: GoogleFonts.dmSans(
                              color: AppColors.text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2)),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: availableDecks.map((d) {
                            final sel = _selectedDeckIds.contains(d.id);
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  if (sel) {
                                    _selectedDeckIds.remove(d.id);
                                  } else {
                                    _selectedDeckIds.add(d.id);
                                  }
                                }),
                                child: _SheetChip(
                                    label: d.name,
                                    color: d.accentColor,
                                    selected: sel,
                                    locked: false),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _selectedDeckIds.isEmpty
                            ? null
                            : () {
                                widget.card.deckIds.addAll(_selectedDeckIds);
                                Navigator.pop(context, _selectedDeckIds.length);
                              },
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            color: _selectedDeckIds.isEmpty
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: _selectedDeckIds.isEmpty
                                ? null
                                : [
                                    BoxShadow(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.3),
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
                              Text('Add to selected decks',
                                  style: GoogleFonts.dmSans(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else
                      const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text('Close',
                            style: GoogleFonts.dmSans(
                                color: AppColors.text2,
                                fontSize: 14,
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

class _PlayCtrlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  const _PlayCtrlBtn({required this.icon, required this.active, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Icon(
          icon,
          size: 18,
          color: active ? AppColors.primary : AppColors.text3,
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ModeTab(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: active ? Colors.white : AppColors.text2),
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.dmSans(
                    color: active ? Colors.white : AppColors.text2,
                    fontSize: 13,
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

class _SheetChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final bool locked;
  const _SheetChip(
      {required this.label,
      required this.color,
      required this.selected,
      required this.locked});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.18) : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1),
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
