import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/deck.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'a word requested from a selected deck is marked in the inspect bar '
      'and the word sheet; a word not from that deck is not', (tester) async {
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

    // "Warszawa" is a lemma that appears in the offline mock text (the
    // Warsaw article) — put it in a deck so it's requested as vocabulary.
    const deck = Deck(id: 'd1', name: 'My Deck', courseId: 'en_pl');
    await AppStorage.instance.saveDecks([deck]);
    await AppStorage.instance.saveFlashcards([
      Flashcard(
          id: 'f1',
          word: 'Warszawa',
          translation: 'Warsaw',
          courseId: 'en_pl',
          deckIds: {'d1'}),
    ]);

    await tester.pumpWidget(const MaterialApp(home: ReadScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    // Select the deck so its vocabulary is requested for this generation.
    await tester.tap(find.text('My Deck'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate').last);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warsaw — Poland\'s Resilient Capital'));
    await tester.pumpAndSettle();

    // "Warszawa" was requested from the selected deck -> marked.
    await tester.tap(find.text('Warszawa').first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.collections_bookmark_rounded).hitTestable(),
        findsOneWidget,
        reason: 'inspect bar must mark a word requested from the deck');
    await tester.tap(find.byIcon(Icons.menu_book_rounded));
    await tester.pumpAndSettle();
    expect(find.text('From your deck'), findsOneWidget);
    await tester.tapAt(const Offset(195, 60)); // dismiss the sheet
    await tester.pumpAndSettle();

    // "jest" was not in the requested vocabulary -> not marked.
    await tester.tap(find.text('jest').first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.collections_bookmark_rounded).hitTestable(),
        findsNothing,
        reason: 'a word outside the requested deck vocabulary must not be '
            'marked');
    await tester.tap(find.byIcon(Icons.menu_book_rounded));
    await tester.pumpAndSettle();
    expect(find.text('From your deck'), findsNothing);
  });
}
