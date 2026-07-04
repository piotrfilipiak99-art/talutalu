import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  testWidgets(
      'a freshly-added card shows a NEW badge the first time Review is '
      'opened, and loses it on the next open',
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
        id: 'fresh-1',
        word: 'nowy',
        translation: 'new',
        courseId: 'en_pl',
      ),
      Flashcard(
        id: 'old-1',
        word: 'stary',
        translation: 'old',
        courseId: 'en_pl',
        seen: true,
        correctCount: 3,
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: FlashcardsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('NEW'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('NEW'), findsNothing);

    final saved =
        AppStorage.instance.flashcards.firstWhere((c) => c.id == 'fresh-1');
    expect(saved.seen, isTrue);
  });
}
