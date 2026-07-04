import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'selecting words in the reader and tapping the discuss button builds '
      'an explain request with rebased tokens and the aligned translation',
      (tester) async {
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

    // Generate and open the mock text (same path as the token tests).
    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate').last);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warsaw — Poland\'s Resilient Capital'));
    await tester.pumpAndSettle();

    // Enter select mode and pick "Warszawa … stolicą" (first three words).
    await tester.tap(find.byIcon(Icons.highlight_alt_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warszawa').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('stolicą').first);
    await tester.pumpAndSettle();

    // The selection panel's discuss button replaces the old copy button.
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.forum_rounded));
    await tester.pumpAndSettle();

    // Only ReadScreen is pumped here — no Converse to consume the request —
    // so the hand-off itself can be inspected.
    final req = AppStorage.instance.explainRequest.value;
    expect(req, isNotNull);
    expect(req!.courseId, 'en_pl');
    expect(req.text, 'Warszawa jest stolicą');
    expect(req.translation,
        'Warsaw is the capital of Poland and the largest city in the country.');

    // Tokens cover exactly the selection, rebased onto the selection text.
    expect(req.tokens.length, 3);
    expect(req.tokens.first.surface, 'Warszawa');
    expect(req.tokens.first.charStart, 0);
    expect(req.tokens.last.surface, 'stolicą');
    expect(req.text.substring(
            req.tokens.last.charStart, req.tokens.last.charEnd),
        'stolicą');

    AppStorage.instance.explainRequest.value = null;
  });
}
