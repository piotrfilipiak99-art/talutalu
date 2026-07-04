import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/screens/converse_screen.dart';

void main() {
  testWidgets(
      'Converse: start a conversation, send a message, get a mock AI reply '
      'whose words can be tapped for translation, then star and delete it',
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

    await tester.pumpWidget(const MaterialApp(home: ConverseScreen()));
    await tester.pumpAndSettle();

    // No conversations yet -> empty state with a start button.
    expect(find.text('No conversations yet'), findsOneWidget);
    await tester.tap(find.text('New conversation'));
    await tester.pumpAndSettle();

    // Send a message and wait out the mock "typing" delay.
    await tester.enterText(find.byType(TextField), 'Cześć!');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    // Also shown as the AppBar title (conversations fall back to the first
    // user message as their display title), so there are two matches.
    expect(find.text('Cześć!'), findsWidgets);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    // First mock reply is "Cześć! Miło Cię poznać." — tap a word in it.
    // The trailing period renders as its own (unhighlighted) Text now, so
    // the tappable word itself is just "poznać".
    await tester.tap(find.text('poznać'));
    await tester.pumpAndSettle();
    // Inspect flow (same as Read): the tap highlights the word and shows
    // the docked bar with the inline gloss; the book button opens the sheet.
    expect(find.text('to meet'), findsOneWidget); // gloss in the bar
    await tester.tap(find.byIcon(Icons.menu_book_rounded));
    await tester.pumpAndSettle();
    expect(find.text('to meet'), findsWidgets); // bar + sheet
    expect(find.text('poznać'), findsWidgets); // sheet header + base form
    await tester.tap(find.text('Add to flashcards'));
    await tester.pumpAndSettle();

    final cards = AppStorage.instance.flashcards;
    expect(cards.any((c) => c.word == 'poznać'), isTrue);

    // Back to the list: star the conversation, then delete it.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Cześć!'), findsOneWidget); // last-message preview

    await tester.tap(find.byIcon(Icons.star_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);

    await tester.drag(find.text('Cześć!').first, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('No conversations yet'), findsOneWidget);
    expect(AppStorage.instance.conversations, isEmpty);
  });
}
