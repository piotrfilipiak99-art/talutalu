import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  test('legacy cards migrate source from fromTexts', () {
    final legacyText = Flashcard.fromJson({
      'id': 'a',
      'word': 'kot',
      'translation': 'cat',
      'courseId': 'en_pl',
      'fromTexts': true,
      'deckIds': <String>[],
    });
    expect(legacyText.source, Flashcard.sourceText);

    final legacyManual = Flashcard.fromJson({
      'id': 'b',
      'word': 'pies',
      'translation': 'dog',
      'courseId': 'en_pl',
      'fromTexts': false,
      'deckIds': <String>[],
    });
    expect(legacyManual.source, Flashcard.sourceManual);

    // Round-trip keeps an explicit source.
    final ai = Flashcard(
        id: 'c',
        word: 'ser',
        translation: 'cheese',
        courseId: 'en_pl',
        source: Flashcard.sourceAi);
    expect(Flashcard.fromJson(ai.toJson()).source, Flashcard.sourceAi);

    // AI-generated and text-sourced cards are locked for editing;
    // manual and converse ones are not.
    expect(ai.isLocked, isTrue);
    expect(legacyText.isLocked, isTrue);
    expect(legacyManual.isLocked, isFalse);
  });

  testWidgets('Review rows show where each card came from', (tester) async {
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
          id: '1',
          word: 'kot',
          translation: 'cat',
          courseId: 'en_pl',
          fromTexts: true),
      Flashcard(
          id: '2',
          word: 'czesc',
          translation: 'hi',
          courseId: 'en_pl',
          source: Flashcard.sourceConverse),
      Flashcard(
          id: '3',
          word: 'ser',
          translation: 'cheese',
          courseId: 'en_pl',
          source: Flashcard.sourceAi),
      Flashcard(
          id: '4',
          word: 'dom',
          translation: 'house',
          courseId: 'en_pl'),
    ]);

    await tester.pumpWidget(const MaterialApp(home: FlashcardsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    // One badge per non-manual origin; the manual card shows none, so
    // there are exactly three origin badges in the list.
    expect(find.text('text'), findsOneWidget);
    expect(find.text('chat'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
  });
}
