import '../models/flashcard.dart';
import 'app_storage.dart';

// ─── Language levels ─────────────────────────────────────────────────────────
// One "language" here means the learning target (e.g. Polish) — points
// merge across every course that teaches it regardless of base language, so
// en→pl and de→pl both feed the same Polish level. Points are the sum of
// each flashcard's peakMasteryLevel — the highest 0-10 mastery it has ever
// reached, not its current one. That's deliberate: masteryLevel can drop
// back down after a wrong answer, but a level-up already earned shouldn't
// be taken back by a later slip.
//
// Level thresholds double each time: 5, +10, +20, +40, ... so level N needs
// a cumulative 5*(2^N - 1) points.

class LanguageLevel {
  final String targetCode;
  final String targetName;
  final String targetFlag;
  final int points;
  const LanguageLevel({
    required this.targetCode,
    required this.targetName,
    required this.targetFlag,
    required this.points,
  });

  int get level => levelForPoints(points);
}

int cumulativeForLevel(int level) => level <= 0 ? 0 : 5 * ((1 << level) - 1);

int levelForPoints(int points) {
  var level = 0;
  while (cumulativeForLevel(level + 1) <= points) {
    level++;
  }
  return level;
}

/// Levels for every learning-target language, sorted by points descending.
/// [cards] and [courses] default to the stored state; pass them explicitly
/// when a screen holds its own working copies.
List<LanguageLevel> computeLanguageLevels({
  List<Flashcard>? cards,
  List<Map<String, String>>? courses,
}) {
  final allCourses = courses ?? AppStorage.instance.courses;
  final allCards = cards ?? AppStorage.instance.flashcards;
  final namesByTarget = <String, Map<String, String>>{};
  final courseIdsByTarget = <String, Set<String>>{};
  for (final c in allCourses) {
    final targetCode = c['targetCode'];
    final baseCode = c['baseCode'];
    if (targetCode == null || targetCode.isEmpty || baseCode == null) continue;
    namesByTarget.putIfAbsent(
        targetCode,
        () => {
              'name': c['targetName'] ?? targetCode,
              'flag': c['targetFlag'] ?? '',
            });
    courseIdsByTarget
        .putIfAbsent(targetCode, () => {})
        .add('${baseCode}_$targetCode');
  }
  final levels = namesByTarget.entries.map((e) {
    final ids = courseIdsByTarget[e.key] ?? const {};
    final points = allCards
        .where((c) => ids.contains(c.courseId))
        .fold<int>(0, (sum, c) => sum + c.peakMasteryLevel);
    return LanguageLevel(
      targetCode: e.key,
      targetName: e.value['name']!,
      targetFlag: e.value['flag']!,
      points: points,
    );
  }).toList();
  levels.sort((a, b) => b.points.compareTo(a.points));
  return levels;
}
