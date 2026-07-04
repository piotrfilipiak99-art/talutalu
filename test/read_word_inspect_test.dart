import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'tapping a word highlights it and shows the inspect panel; arrows step '
      'between words and the book button opens the word sheet', (tester) async {
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

    await tester.pumpWidget(const MaterialApp(home: ReadScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate').last);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warsaw — Poland\'s Resilient Capital'));
    await tester.pumpAndSettle();

    // No panel and no sheet before any tap (the panel widget lives in the
    // tree but sits off-screen, so hit-testability is the real signal).
    expect(find.byIcon(Icons.menu_book_rounded).hitTestable(), findsNothing);

    // Tapping a word does NOT open the sheet anymore — it highlights the
    // word and reveals the inspect panel.
    await tester.tap(find.text('Warszawa').first);
    await tester.pumpAndSettle();
    expect(find.text('proper noun'), findsNothing,
        reason: 'word sheet must not open on plain tap');
    expect(find.byIcon(Icons.menu_book_rounded).hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded).hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded).hitTestable(), findsOneWidget);
    // The bar shows the word's gloss inline, without opening the sheet.
    expect(find.text('Warsaw').hitTestable(), findsOneWidget);

    // The book button opens the word sheet for the highlighted word.
    await tester.tap(find.byIcon(Icons.menu_book_rounded));
    await tester.pumpAndSettle();
    expect(find.text('proper noun'), findsOneWidget);
    await tester.tapAt(const Offset(195, 60)); // dismiss the sheet
    await tester.pumpAndSettle();

    // The right arrow moves the highlight to the next word — opening the
    // sheet now shows a different word ("jest" -> verb, not proper noun).
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.menu_book_rounded));
    await tester.pumpAndSettle();
    expect(find.text('proper noun'), findsNothing);
    await tester.tapAt(const Offset(195, 60));
    await tester.pumpAndSettle();

    // Tapping the same word again clears the highlight and hides the panel.
    await tester.tap(find.text('jest').first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.menu_book_rounded).hitTestable(), findsNothing);
  });
}
