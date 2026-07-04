import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'Read word sheet: "New deck" in Add to deck creates a deck and '
      'selects it, then Add to flashcards assigns the card to it',
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

    expect(AppStorage.instance.decks, isEmpty);
    await tester.ensureVisible(find.text('New deck'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New deck'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Capitals');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(AppStorage.instance.decks.map((d) => d.name), contains('Capitals'));
    expect(find.text('Capitals'), findsOneWidget);

    await tester.tap(find.text('Add to flashcards'));
    await tester.pumpAndSettle();

    final card =
        AppStorage.instance.flashcards.firstWhere((c) => c.word == 'Warszawa');
    final deck = AppStorage.instance.decks.firstWhere((d) => d.name == 'Capitals');
    expect(card.deckIds, contains(deck.id));
  });
}
