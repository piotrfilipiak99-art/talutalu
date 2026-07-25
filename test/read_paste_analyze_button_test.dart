import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/screens/read_screen.dart';

void main() {
  testWidgets(
      'pasting your own text shows an "Analyze" button (not "Add text") and, '
      'without a session to analyze with, still inserts the text instantly',
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

    await tester.tap(find.text('New text'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();

    expect(find.text('Analyze'), findsOneWidget);
    expect(find.text('Add text'), findsNothing);

    await tester.enterText(
        find.byType(TextField), 'To jest moj wlasny tekst.');
    await tester.tap(find.text('Analyze'));
    await tester.pumpAndSettle();

    // No session -> falls back to a plain (non-interactive) insert rather
    // than calling the backend; the pasted body is still saved as-is (the
    // list item shows a mock title, not the body, so check storage).
    expect(AppStorage.instance.texts.first['body'],
        'To jest moj wlasny tekst.');
  });
}
