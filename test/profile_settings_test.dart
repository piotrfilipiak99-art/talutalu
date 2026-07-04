import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/theme/app_theme.dart';
import 'package:talutalu/screens/home_screen.dart';

void main() {
  Future<void> setUp(WidgetTester tester) async {
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
  }

  testWidgets(
      'Appearance sheet flips dark mode, persists it, and shows it selected '
      'the next time the sheet opens', (tester) async {
    await setUp(tester);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(AppStorage.instance.darkMode.value, isTrue);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();

    expect(AppStorage.instance.darkMode.value, isFalse);
    expect(AppColors.isDark, isFalse);
    expect(find.text('Light'), findsOneWidget); // trailing label on the tile

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('darkMode'), isFalse);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('Edit profile changes the username and it shows on Profile',
      (tester) async {
    await setUp(tester);
    await AppStorage.instance.saveProfile('Old Name', '');

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Old Name'), findsOneWidget);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'New Name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(AppStorage.instance.userName, 'New Name');
    expect(find.text('New Name'), findsOneWidget);
  });

  testWidgets(
      'Notifications: the daily reminder is gated by the master switch',
      (tester) async {
    await setUp(tester);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();

    // Notifications master switch is on by default; the reminder isn't.
    expect(AppStorage.instance.notificationsEnabled, isTrue);
    expect(AppStorage.instance.reminderEnabled, isFalse);

    final reminderSwitch = find.ancestor(
        of: find.text('Daily reminder'), matching: find.byType(Row));
    expect(reminderSwitch, findsOneWidget);
    await tester.tap(find.descendant(
        of: reminderSwitch, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(AppStorage.instance.reminderEnabled, isTrue);
    expect(find.text('Time'), findsOneWidget);

    // Turning notifications off should turn the reminder off with it, and
    // disable the reminder switch so it can't be re-enabled independently.
    final masterSwitch = find.ancestor(
        of: find.byIcon(Icons.notifications_active_rounded),
        matching: find.byType(Row));
    await tester.tap(find.descendant(
        of: masterSwitch, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(AppStorage.instance.notificationsEnabled, isFalse);
    expect(AppStorage.instance.reminderEnabled, isFalse);
    expect(find.text('Time'), findsNothing);

    final reminderSwitchWidget = tester.widget<Switch>(find.descendant(
        of: find.ancestor(
            of: find.text('Daily reminder'), matching: find.byType(Row)),
        matching: find.byType(Switch)));
    expect(reminderSwitchWidget.onChanged, isNull);
  });
}
