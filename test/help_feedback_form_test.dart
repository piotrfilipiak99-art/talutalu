import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:talutalu/screens/help_feedback_screen.dart';

void main() {
  testWidgets(
      'Help & feedback form: sending needs a message, then shows a '
      'confirmation and returns to the previous screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: HelpFeedbackScreen()));
    await tester.pumpAndSettle();

    // Empty message blocks sending.
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Please write a message before sending.'), findsOneWidget);
    expect(find.text('Message sent'), findsNothing);

    // Pick a topic and write a message.
    await tester.tap(find.text('Suggestion'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).last, 'More Polish grammar drills, please!');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Message sent'), findsOneWidget);

    // Dismissing the confirmation leaves the form screen too.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(HelpFeedbackScreen), findsNothing);
  });
}
