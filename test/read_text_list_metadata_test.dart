import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/deck.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'the text list shows a relative generation date, and a deck badge '
      'only when vocabulary decks were selected', (tester) async {
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
    const deck = Deck(id: 'd1', name: 'My Deck', courseId: 'en_pl');
    await AppStorage.instance.saveDecks([deck]);

    await tester.pumpWidget(const MaterialApp(home: ReadScreen()));
    await tester.pumpAndSettle();

    // Generate a text WITHOUT selecting any deck.
    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate').last);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    // Back on the list: a date shows, no deck badge for this text.
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('My Deck'), findsNothing);

    // Generate a second text WITH the deck selected.
    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Deck'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate').last);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    // Two texts now share the same mock title, so match by count instead
    // of a unique finder: one "Today" date per list item, and exactly one
    // deck badge (from the second text only).
    expect(find.text('Today'), findsNWidgets(2));
    expect(find.text('My Deck'), findsOneWidget);
  });
}
