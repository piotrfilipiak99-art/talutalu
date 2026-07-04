import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/deck.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'adding an already-flashcarded word offers to extend it to more '
      'decks instead of silently rejecting it or creating a duplicate',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Same google_fonts test-harness caveat as read_screen_token_test.dart.
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

    // Two user decks; the word is already filed under "Travel".
    await AppStorage.instance.saveDecks(const [
      Deck(id: 'travel', name: 'Travel', courseId: 'en_pl'),
      Deck(id: 'nature', name: 'Nature', courseId: 'en_pl'),
    ]);
    await AppStorage.instance.saveFlashcards([
      Flashcard(
        id: 'existing-1',
        word: 'Warszawa',
        translation: 'Warsaw',
        wordType: 'proper noun',
        courseId: 'en_pl',
        fromTexts: true,
        deckIds: {'travel'},
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: ReadScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate').last);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Warsaw — Poland\'s Resilient Capital'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Warszawa').first);
    await tester.pumpAndSettle();

    // Trigger add-to-flashcards without picking any extra deck in the word
    // sheet itself — the duplicate should still be detected.
    await tester.tap(find.text('Add to flashcards'));
    await tester.pumpAndSettle();

    expect(find.text('Already in your flashcards'), findsOneWidget);
    expect(find.textContaining('Travel'), findsOneWidget);

    await tester.tap(find.text('Nature'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to selected decks'));
    await tester.pumpAndSettle();

    expect(find.textContaining('added to 1 more deck'), findsOneWidget);

    final saved = AppStorage.instance.flashcards
        .firstWhere((c) => c.word == 'Warszawa');
    expect(saved.deckIds, {'travel', 'nature'});
  });
}
