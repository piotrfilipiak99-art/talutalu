import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/services/language_levels.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  test('level thresholds double each time: 5, 15, 35, ... cumulative', () {
    expect(levelForPoints(0), 0);
    expect(levelForPoints(4), 0);
    expect(levelForPoints(5), 1);
    expect(levelForPoints(14), 1);
    expect(levelForPoints(15), 2);
    expect(levelForPoints(35), 3);
  });

  testWidgets(
      'grading the answer that pushes a language over a level threshold '
      'shows the level-up celebration naming that language', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    SharedPreferences.setMockInitialValues({});
    await AppStorage.instance.init();

    const base = {'code': 'en', 'name': 'English', 'flag': '🇬🇧'};
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
    await AppStorage.instance.saveCourseState(
      bases: const [base],
      courses: const [enToPl, deToPl],
      selectedBase: 'en',
      activeCourse: enToPl,
    );

    // Polish sits at 4 points — one point short of level 1 (threshold 5).
    // The de_pl cards keep the practiced deck down to the single fresh card
    // while still feeding the same Polish level.
    await AppStorage.instance.saveFlashcards([
      Flashcard(
        id: 'fresh-1',
        word: 'pies',
        translation: 'dog',
        courseId: 'en_pl',
      ),
      for (var i = 0; i < 4; i++)
        Flashcard(
          id: 'de-$i',
          word: 'w$i',
          translation: 't$i',
          courseId: 'de_pl',
          seen: true,
          correctCount: 1,
          peakMasteryLevel: 1,
        ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: FlashcardsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dog');
    await tester.tap(find.text('Check'));
    // The celebration keeps a looping ray animation running, so
    // pumpAndSettle would never settle — pump past the pop-in instead.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('LEVEL UP'), findsOneWidget);
    expect(find.text('Polish · Level 1'), findsOneWidget);
    expect(find.textContaining('You reached level 1 in Polish'),
        findsOneWidget);

    // Dismiss and make sure it doesn't linger.
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('LEVEL UP'), findsNothing);

    // The graded card really earned the point that crossed the threshold.
    final saved =
        AppStorage.instance.flashcards.firstWhere((c) => c.id == 'fresh-1');
    expect(saved.peakMasteryLevel, 1);
  });
}
