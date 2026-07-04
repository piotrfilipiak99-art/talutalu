import 'dart:math';
import 'package:flutter/material.dart';

class Flashcard {
  final String id;
  String word;
  String translation;
  String? wordType;
  final String courseId;

  /// True when this card was imported from a reading text.
  /// Immutable — cannot be changed through the edit UI.
  final bool fromTexts;

  /// User-deck IDs this card belongs to (multi-deck).
  /// General and From Texts are virtual — never stored here.
  Set<String> deckIds;

  /// Grammatical attributes of the word itself (gender, aspect, ...) —
  /// carried over from the source TextToken when added from a text, same
  /// UD-style keys/values as lib/models/text_token.dart. Empty/null when
  /// the card wasn't created from an analyzed text.
  Map<String, String>? morph;
  String? root;
  String? rootMeaning;

  /// True once the card has been shown in Review at least once, or
  /// practiced (graded) at least once in Write/Quiz/Match. Drives the
  /// "NEW" badge in Review — separate from [isNew], which just reflects
  /// whether it's ever been graded.
  bool seen;

  /// Highest [masteryLevel] this card has ever reached. Unlike
  /// [masteryLevel] itself — which can drop back down after a wrong
  /// answer — this only ever goes up, since it's what backs the language
  /// point/level system in Profile: leveling up awards a point that a
  /// later slip shouldn't take back.
  int peakMasteryLevel;

  int correctCount;
  int incorrectCount;

  /// Outcomes of the most recent grades (true = correct), capped at
  /// [resultWindow] entries — the sliding window behind the percentage
  /// phase of [masteryLevel]. Cards saved before this field existed start
  /// empty and refill as they get graded.
  List<bool> recentResults;

  /// 0–10 mastery level. Two phases:
  ///  - Counter phase (10 or fewer recorded results): +1 per correct
  ///    answer, -1 per wrong one.
  ///  - Percentage phase (more than [counterPhaseGrades] recorded
  ///    results): the share of correct answers within [recentResults],
  ///    rounded to the nearest level (e.g. 72% -> 7).
  /// In both phases the level is clamped to [1, 10] once the card has been
  /// graded at all (0 is reserved for never-graded cards), and a wrong
  /// answer can never raise it: on a wrong answer the new value is capped
  /// at the previous one, so the one-time jump when a card crosses from
  /// the counter scale to the percentage scale (which usually rates the
  /// same history higher) only shows up after a correct answer.
  int masteryLevel;

  int intervalDays;
  double easeFactor;
  DateTime nextReview;
  final DateTime createdAt;

  /// How many grades the counter (+1/-1) phase lasts before the
  /// percentage phase takes over.
  static const int counterPhaseGrades = 10;

  /// How many most-recent results the percentage phase is computed from.
  static const int resultWindow = 20;

  Flashcard({
    required this.id,
    required this.word,
    required this.translation,
    this.wordType,
    required this.courseId,
    this.fromTexts = false,
    Set<String>? deckIds,
    this.morph,
    this.root,
    this.rootMeaning,
    this.seen = false,
    this.peakMasteryLevel = 0,
    this.correctCount = 0,
    this.incorrectCount = 0,
    List<bool>? recentResults,
    this.masteryLevel = 0,
    this.intervalDays = 1,
    this.easeFactor = 2.5,
    DateTime? nextReview,
    DateTime? createdAt,
  })  : deckIds = deckIds ?? {},
        recentResults = recentResults ?? [],
        nextReview = nextReview ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now();

  int get total => correctCount + incorrectCount;
  double get masteryPercent => total == 0 ? 0 : correctCount / total * 100;
  bool get isDue => !DateTime.now().isBefore(nextReview);
  bool get isNew => total == 0;

  static Color _levelColor(int level) {
    if (level == 0) return const Color(0xFF6B6880);
    final hue = (level - 1) / 9 * 120.0;
    return HSLColor.fromAHSL(1.0, hue, 0.72, 0.54).toColor();
  }

  Color get masteryColor => _levelColor(masteryLevel);

  void _bumpPeak() {
    if (masteryLevel > peakMasteryLevel) peakMasteryLevel = masteryLevel;
  }

  void _recordAnswer(bool correct) {
    if (correct) {
      correctCount++;
    } else {
      incorrectCount++;
    }
    recentResults.add(correct);
    if (recentResults.length > resultWindow) recentResults.removeAt(0);

    // Migrated cards with pre-window history sit in the counter phase (over
    // their lifetime counters) until they accumulate enough fresh results.
    final int candidate;
    if (recentResults.length <= counterPhaseGrades) {
      candidate = max(1, min(10, correctCount - incorrectCount));
    } else {
      final right = recentResults.where((r) => r).length;
      candidate =
          max(1, min(10, (right / recentResults.length * 10).round()));
    }
    // The level-1 floor outranks the no-rise-on-wrong cap: a card's very
    // first grade lifts it from the never-graded 0 even when it's wrong.
    masteryLevel =
        max(1, correct ? candidate : min(masteryLevel, candidate));
    _bumpPeak();
  }

  void applyEasy() {
    _recordAnswer(true);
    easeFactor = min(3.0, easeFactor + 0.15);
    intervalDays = intervalDays <= 1 ? 4 : (intervalDays * easeFactor).round();
    nextReview = DateTime.now().add(Duration(days: intervalDays));
  }

  void applyHard() {
    _recordAnswer(true);
    easeFactor = max(1.3, easeFactor - 0.2);
    intervalDays = max(1, (intervalDays * 0.8).round());
    nextReview = DateTime.now().add(Duration(days: intervalDays));
  }

  void applyAgain() {
    _recordAnswer(false);
    easeFactor = max(1.3, easeFactor - 0.3);
    intervalDays = 1;
    nextReview = DateTime.now().add(const Duration(days: 1));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'word': word,
        'translation': translation,
        'wordType': wordType,
        'courseId': courseId,
        'fromTexts': fromTexts,
        'deckIds': deckIds.toList(),
        'morph': morph,
        'root': root,
        'rootMeaning': rootMeaning,
        'seen': seen,
        'peakMasteryLevel': peakMasteryLevel,
        'correctCount': correctCount,
        'incorrectCount': incorrectCount,
        'recentResults': recentResults,
        'masteryLevel': masteryLevel,
        'intervalDays': intervalDays,
        'easeFactor': easeFactor,
        'nextReview': nextReview.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory Flashcard.fromJson(Map<String, dynamic> j) {
    // Migrate old single-deckId format → new multi-deck format
    bool fromTexts;
    Set<String> deckIds;
    if (j.containsKey('deckIds')) {
      fromTexts = (j['fromTexts'] as bool?) ?? false;
      deckIds = Set<String>.from((j['deckIds'] as List?) ?? []);
    } else {
      final oldId = (j['deckId'] as String?) ?? 'general';
      fromTexts = oldId == 'from_texts';
      deckIds =
          (oldId != 'general' && oldId != 'from_texts') ? {oldId} : {};
    }

    return Flashcard(
      id: j['id'] as String,
      word: j['word'] as String,
      translation: j['translation'] as String,
      wordType: j['wordType'] as String?,
      courseId: j['courseId'] as String,
      fromTexts: fromTexts,
      deckIds: deckIds,
      morph: j['morph'] == null
          ? null
          : Map<String, String>.from(j['morph'] as Map),
      root: j['root'] as String?,
      rootMeaning: j['rootMeaning'] as String?,
      // Cards saved before this field existed: treat any card that already
      // has practice history as seen, so old progress isn't relabelled NEW.
      seen: (j['seen'] as bool?) ?? (_migratedTotal(j) > 0),
      // Cards saved before peakMasteryLevel existed have no record of their
      // history, so the best available stand-in is their current level —
      // it'll only grow correctly from here on.
      peakMasteryLevel:
          (j['peakMasteryLevel'] as int?) ?? _migratedMasteryLevel(j),
      correctCount: (j['correctCount'] as int?) ?? 0,
      incorrectCount: (j['incorrectCount'] as int?) ?? 0,
      recentResults: List<bool>.from((j['recentResults'] as List?) ?? const []),
      // Cards saved before the stored level existed: reconstruct it from the
      // lifetime counters with the old counter formula (plus the new
      // graded-cards-never-show-0 floor).
      masteryLevel: (j['masteryLevel'] as int?) ?? _migratedMasteryLevel(j),
      intervalDays: (j['intervalDays'] as int?) ?? 1,
      easeFactor: ((j['easeFactor'] as num?) ?? 2.5).toDouble(),
      nextReview: j['nextReview'] != null
          ? DateTime.parse(j['nextReview'] as String)
          : DateTime.now(),
      createdAt: j['createdAt'] != null
          ? DateTime.parse(j['createdAt'] as String)
          : DateTime.now(),
    );
  }

  static int _migratedTotal(Map<String, dynamic> j) =>
      ((j['correctCount'] as int?) ?? 0) + ((j['incorrectCount'] as int?) ?? 0);

  static int _migratedMasteryLevel(Map<String, dynamic> j) {
    final correct = (j['correctCount'] as int?) ?? 0;
    final incorrect = (j['incorrectCount'] as int?) ?? 0;
    if (correct + incorrect == 0) return 0;
    return max(1, min(10, correct - incorrect));
  }
}
