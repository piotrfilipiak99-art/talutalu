import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/profile_screen.dart';

void main() {
  testWidgets(
      'Profile shows a Levels section that merges points for a learned '
      'language across different base-language courses', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('RenderFlex overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    SharedPreferences.setMockInitialValues({});
    await AppStorage.instance.init();

    const enBase = {'code': 'en', 'name': 'English', 'flag': '🇬🇧'};
    const enToPl = {
      'targetCode': 'pl',
      'targetName': 'Polish',
      'targetFlag': '🇵🇱',
      'baseCode': 'en',
      'baseName': 'English',
      'baseFlag': '🇬🇧',
    };
    const deToPl = {
      'targetCode': 'pl',
      'targetName': 'Polish',
      'targetFlag': '🇵🇱',
      'baseCode': 'de',
      'baseName': 'German',
      'baseFlag': '🇩🇪',
    };
    const enToEs = {
      'targetCode': 'es',
      'targetName': 'Spanish',
      'targetFlag': '🇪🇸',
      'baseCode': 'en',
      'baseName': 'English',
      'baseFlag': '🇬🇧',
    };
    await AppStorage.instance.saveCourseState(
      bases: const [enBase],
      courses: const [enToPl, deToPl, enToEs],
      selectedBase: 'en',
      activeCourse: enToPl,
    );

    Flashcard card(String courseId, String word, int correct) => Flashcard(
          id: '$courseId-$word',
          word: word,
          translation: word,
          courseId: courseId,
          correctCount: correct,
          // Points are driven by peakMasteryLevel, not the live masteryLevel
          // getter — set explicitly here to match what correctCount alone
          // would produce, same as if these cards had been graded via
          // applyEasy() one call per point.
          peakMasteryLevel: correct,
        );

    // en_pl + de_pl both target Polish -> their masteryLevels must merge.
    await AppStorage.instance.saveFlashcards([
      card('en_pl', 'a', 1), // masteryLevel 1
      card('en_pl', 'b', 1), // masteryLevel 1
      card('en_pl', 'c', 1), // masteryLevel 1
      card('de_pl', 'd', 2), // masteryLevel 2
      card('en_es', 'e', 1), // masteryLevel 1 (separate language: Spanish)
    ]);

    await tester.pumpWidget(const MaterialApp(home: ProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('LEVELS'), findsOneWidget);
    expect(find.text('Polish'), findsOneWidget);
    expect(find.text('Spanish'), findsOneWidget);

    // Polish: 1+1+1 (en_pl) + 2 (de_pl) = 5 points -> level 1 (5 = threshold
    // for level 1). Spanish: 1 point -> level 0 (below the 5-point threshold).
    expect(find.text('Lvl 1'), findsOneWidget);
    expect(find.text('Lvl 0'), findsOneWidget);

    // The numeric caption under the progress bar was removed on purpose —
    // the bar alone shows progress toward the next level.
    expect(find.textContaining('pts to level'), findsNothing);
  });
}
