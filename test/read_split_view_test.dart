import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'split view button divides the reader into text and translation panes '
      'and there is no Continue button anymore', (tester) async {
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

    // Generate a mock text (offline path) and open it.
    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate').last);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Warsaw — Poland\'s Resilient Capital'));
    await tester.pumpAndSettle();

    // The Continue feature is gone.
    expect(find.textContaining('Continue'), findsNothing);

    // Split view off: one scroll view; the inline translation panel exists
    // but is collapsed, so its words can't be hit.
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Warsaw').hitTestable(), findsNothing);

    // Toggle split view via the new button next to Translation.
    await tester.tap(find.byIcon(Icons.splitscreen_rounded));
    await tester.pumpAndSettle();

    // Both panes are live now: two scrollables, body words on top and
    // actually-tappable translation words below.
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    expect(find.text('Warszawa').hitTestable(), findsWidgets);
    expect(find.text('Warsaw').hitTestable(), findsWidgets);
    // The split panes are self-explanatory — no TRANSLATION label.
    expect(find.text('TRANSLATION'), findsNothing);

    // Toggling again returns to the single-pane reader.
    await tester.tap(find.byIcon(Icons.splitscreen_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Warsaw').hitTestable(), findsNothing);
  });
}
