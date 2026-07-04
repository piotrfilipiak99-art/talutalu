import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  testWidgets(
      'Review card detail sheet: text-sourced (locked) cards can still '
      'create and be assigned to a new deck — only word/type stay locked',
      (tester) async {
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

    const base = {'code': 'en', 'name': 'English', 'flag': '🇬🇧'};
    const course = {
      'targetCode': 'pl',
      'targetName': 'Polish',
      'targetFlag': '🇵🇱',
      'baseCode': 'en',
      'baseName': 'English',
      'baseFlag': '🇬🇧',
    };
    await AppStorage.instance.saveCourseState(
      bases: const [base],
      courses: const [course],
      selectedBase: 'en',
      activeCourse: course,
    );

    await AppStorage.instance.saveFlashcards([
      Flashcard(
        id: 'locked-1',
        word: 'zamek',
        translation: 'castle',
        courseId: 'en_pl',
        fromTexts: true,
        seen: true,
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: FlashcardsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('zamek'));
    await tester.pumpAndSettle();

    expect(find.text('New deck'), findsOneWidget);
    await tester.tap(find.text('New deck'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Buildings');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Buildings'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved =
        AppStorage.instance.flashcards.firstWhere((c) => c.id == 'locked-1');
    final deck = AppStorage.instance.decks.firstWhere((d) => d.name == 'Buildings');
    expect(saved.deckIds, contains(deck.id));
    // Word itself must still stay locked to what the analyzer produced.
    expect(saved.word, 'zamek');
  });
}
