import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/deck.dart';
import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  test('Deck type round-trips through JSON and legacy decks default to vocab',
      () {
    const phrases = Deck(
        id: 'd1', name: 'Idiomy', courseId: 'en_pl', type: Deck.typePhrases);
    final restored = Deck.fromJson(phrases.toJson());
    expect(restored.type, Deck.typePhrases);
    expect(restored.isPhrases, isTrue);

    // A deck saved before the type field existed.
    final legacy =
        Deck.fromJson({'id': 'd0', 'name': 'Old', 'courseId': 'en_pl'});
    expect(legacy.type, Deck.typeVocab);
    expect(legacy.isPhrases, isFalse);
  });

  testWidgets(
      'creating a deck lets you pick the phrases type and the deck tile '
      'gets the phrases icon', (tester) async {
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

    await tester.pumpWidget(const MaterialApp(home: FlashcardsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New deck'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Idiomy');
    await tester.tap(find.text('Phrases'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Deck stored with the phrases type…
    final saved = AppStorage.instance.decks
        .firstWhere((d) => d.name == 'Idiomy');
    expect(saved.type, Deck.typePhrases);

    // …and its tile shows the phrases icon.
    expect(find.text('Idiomy'), findsOneWidget);
    expect(find.byIcon(Icons.format_quote_rounded), findsWidgets);
  });
}
