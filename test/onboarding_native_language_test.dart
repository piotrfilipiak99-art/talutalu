import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/screens/onboarding_screen.dart';

void main() {
  testWidgets(
      'onboarding asks for the native language after the personal page and '
      'blocks Continue until one is picked', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await AppStorage.instance.init();

    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pumpAndSettle();

    // Page 0: pick the first avatar and continue.
    await tester.tap(find.descendant(
      of: find.byType(GridView),
      matching: find.byType(GestureDetector),
    ).first);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Page 1: name + hobby.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Piotr');
    await tester.enterText(fields.at(1), 'chess');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Page 2: the new native-language step.
    expect(find.textContaining('native language'), findsOneWidget);

    // Continue must be inert until a language is selected: still on page 2.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('native language'), findsOneWidget);

    await tester.tap(find.text('Polski'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // Page 3: the course picker.
    expect(find.textContaining('want to learn'), findsOneWidget);
  });
}
