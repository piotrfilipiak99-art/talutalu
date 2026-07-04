import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  testWidgets(
      'tapping a card in Review opens a detail sheet with attributes, '
      'translation, and root pulled from the stored Flashcard fields',
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

    final card = Flashcard(
      id: '1',
      word: 'stolica',
      translation: 'capital',
      wordType: 'noun',
      courseId: 'en_pl',
      fromTexts: true,
      morph: const {'Gender': 'Fem'},
      root: 'stoł-',
      rootMeaning: "throne, seat — historically from 'stół' (table)",
    );
    await AppStorage.instance.saveFlashcards([card]);

    await tester.pumpWidget(const MaterialApp(home: FlashcardsScreen()));
    await tester.pumpAndSettle();

    // Hub -> General deck -> Review activity -> tap the card.
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('stolica').first);
    await tester.pumpAndSettle();

    expect(find.text('Gender: Feminine'), findsOneWidget);
    expect(find.text('capital'), findsWidgets); // also in the list row behind
    expect(find.textContaining('stoł-'), findsOneWidget);
    expect(find.textContaining("from 'stół'"), findsOneWidget);
  });
}
