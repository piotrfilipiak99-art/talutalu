import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/services/app_storage.dart';
import 'package:talutalu/models/explain_request.dart';
import 'package:talutalu/models/text_token.dart';
import 'package:talutalu/screens/home_screen.dart';

void main() {
  testWidgets(
      'an explain request from Read switches to the Converse tab and opens '
      'a new conversation where the AI walks through the sentence',
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

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    // Read is the initial tab.
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);

    // The hand-off Read's selection panel performs.
    AppStorage.instance.explainRequest.value = const ExplainRequest(
      courseId: 'en_pl',
      text: 'Kot pije mleko.',
      translation: 'The cat drinks milk.',
      tokens: [
        TextToken(
            surface: 'Kot',
            lemma: 'kot',
            translation: 'cat',
            lemmaTranslation: 'cat',
            pos: 'NOUN',
            morph: {'Case': 'Nom', 'Gender': 'Masc'},
            sentenceIndex: 0,
            charStart: 0,
            charEnd: 3),
        TextToken(
            surface: 'pije',
            lemma: 'pić',
            translation: 'drinks',
            lemmaTranslation: 'to drink',
            pos: 'VERB',
            morph: {'Person': '3', 'Tense': 'Pres'},
            sentenceIndex: 0,
            charStart: 4,
            charEnd: 8),
        TextToken(
            surface: 'mleko.',
            lemma: 'mleko',
            translation: 'milk',
            lemmaTranslation: 'milk',
            pos: 'NOUN',
            morph: {'Case': 'Acc', 'Gender': 'Neut'},
            sentenceIndex: 0,
            charStart: 9,
            charEnd: 15),
      ],
    );
    await tester.pumpAndSettle();

    // Switched to the Converse tab, straight into the new chat.
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 2);
    expect(find.text('Explain: Kot pije mleko.'), findsOneWidget);

    // First AI message: the sentence itself, word-tappable (each word is
    // its own tap target, so the full sentence isn't one Text widget).
    expect(find.text('Kot'), findsOneWidget);
    expect(find.text('pije'), findsOneWidget);

    // Second AI message: the walkthrough of the sentence's elements.
    expect(find.textContaining('It means: "The cat drinks milk."'),
        findsOneWidget);
    expect(find.textContaining('Word by word:'), findsOneWidget);
    expect(find.textContaining('Base form: pić'), findsOneWidget);

    // The conversation is a real saved thread, entirely from the AI side,
    // and the one-shot request has been consumed.
    final saved = AppStorage.instance.conversations.first;
    expect(saved.messages.length, 2);
    expect(saved.messages.every((m) => !m.fromUser), isTrue);
    expect(AppStorage.instance.explainRequest.value, isNull);

    // Tapping a word in the sentence bubble opens the word sheet, like any
    // AI message.
    await tester.tap(find.text('pije'));
    await tester.pumpAndSettle();
    expect(find.text('to drink'), findsOneWidget);
  });
}
