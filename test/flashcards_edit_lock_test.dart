import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  testWidgets(
      'Review merges info + edit into one sheet; text-sourced cards only '
      'allow editing the translation, manually-added cards allow full edit',
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
      Flashcard(
        id: 'free-1',
        word: 'dom',
        translation: 'house',
        courseId: 'en_pl',
        seen: true,
      ),
    ]);

    await tester.pumpWidget(const MaterialApp(home: FlashcardsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    // Text-sourced card: word locked (plain text, no TextField for it),
    // only the translation TextField is present, plus a lock hint.
    await tester.tap(find.text('zamek'));
    await tester.pumpAndSettle();
    expect(find.text('zamek'), findsWidgets);
    expect(find.textContaining('only the translation can be edited'),
        findsOneWidget);
    expect(find.widgetWithText(TextField, 'castle'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Edit just the translation and save.
    await tester.enterText(find.byType(TextField), 'fortress');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final lockedSaved =
        AppStorage.instance.flashcards.firstWhere((c) => c.id == 'locked-1');
    expect(lockedSaved.translation, 'fortress');
    expect(lockedSaved.word, 'zamek');

    // Manually-added card: both word and translation are editable fields.
    await tester.tap(find.text('dom'));
    await tester.pumpAndSettle();
    expect(find.textContaining('only the translation can be edited'),
        findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    // Dismiss the sheet by tapping the modal barrier above it, then
    // long-press the card — it should open the same merged sheet.
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('dom'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
