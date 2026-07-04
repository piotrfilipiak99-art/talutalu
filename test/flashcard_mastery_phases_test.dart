import 'package:flutter_test/flutter_test.dart';
import 'package:talutalu/models/flashcard.dart';

Flashcard newCard() => Flashcard(
      id: '1',
      word: 'test',
      translation: 'test',
      courseId: 'en_pl',
    );

void main() {
  test('a graded card never shows level 0 — even a first wrong answer '
      'lands on the level-1 floor, only never-graded cards show 0', () {
    final card = newCard();
    expect(card.masteryLevel, 0);

    card.applyAgain();
    expect(card.masteryLevel, 1);

    card.applyAgain();
    expect(card.masteryLevel, 1); // floor holds, doesn't sink to 0
  });

  test('counter phase: first 10 grades move the level by +1/-1', () {
    final card = newCard();
    for (var i = 0; i < 6; i++) {
      card.applyEasy();
    }
    expect(card.masteryLevel, 6);

    card.applyAgain();
    expect(card.masteryLevel, 5);
  });

  test('percentage phase: past 10 grades the level is the rounded share '
      'of correct answers in the recent window', () {
    final card = newCard();
    for (var i = 0; i < 14; i++) {
      card.applyEasy();
    }
    expect(card.masteryLevel, 10);

    for (var i = 0; i < 6; i++) {
      card.applyAgain();
    }
    // Window now holds 14 correct / 6 wrong = 70% -> level 7.
    expect(card.masteryLevel, 7);
  });

  test('the window slides: only the last ${Flashcard.resultWindow} results '
      'count, older ones stop weighing the level down or up', () {
    final card = newCard();
    for (var i = 0; i < 20; i++) {
      card.applyEasy();
    }
    expect(card.masteryLevel, 10);

    for (var i = 0; i < 10; i++) {
      card.applyAgain();
    }
    // Window: the 10 most recent correct + 10 wrong = 50% -> level 5.
    expect(card.masteryLevel, 5);
    expect(card.recentResults.length, Flashcard.resultWindow);
  });

  test('crossing from the counter scale to the percentage scale cannot '
      'raise the level on a wrong answer — the jump waits for a correct one',
      () {
    final card = newCard();
    for (var i = 0; i < 6; i++) {
      card.applyEasy();
    }
    for (var i = 0; i < 4; i++) {
      card.applyAgain();
    }
    // 10 grades, counter phase: 6 - 4 = 2.
    expect(card.masteryLevel, 2);

    // 11th grade is wrong. The percentage scale rates this history 6/11 =
    // 55% -> 5, but a wrong answer must never raise the level.
    card.applyAgain();
    expect(card.masteryLevel, 2);

    // The next correct answer is allowed to jump to the percentage value:
    // 7/12 = 58% -> 6.
    card.applyEasy();
    expect(card.masteryLevel, 6);
  });

  test('cards saved before the stored level existed migrate from their '
      'lifetime counters, with the level-1 floor for graded cards', () {
    Map<String, dynamic> json(int correct, int incorrect) => {
          'id': 'x',
          'word': 'w',
          'translation': 't',
          'courseId': 'en_pl',
          'correctCount': correct,
          'incorrectCount': incorrect,
        };

    expect(Flashcard.fromJson(json(0, 0)).masteryLevel, 0);
    expect(Flashcard.fromJson(json(5, 5)).masteryLevel, 1); // floor
    expect(Flashcard.fromJson(json(7, 2)).masteryLevel, 5);
    expect(Flashcard.fromJson(json(30, 2)).masteryLevel, 10); // cap

    final card = Flashcard.fromJson(json(7, 2));
    expect(card.recentResults, isEmpty);
    // No stored window yet -> stays on the counter scale until enough
    // fresh results accumulate.
    card.applyAgain();
    expect(card.masteryLevel, 4); // lifetime counters: 7 - 3 = 4
  });

  test('masteryLevel and recentResults survive a save/load round trip', () {
    final card = newCard();
    for (var i = 0; i < 12; i++) {
      card.applyEasy();
    }
    card.applyAgain();

    final restored = Flashcard.fromJson(card.toJson());
    expect(restored.masteryLevel, card.masteryLevel);
    expect(restored.recentResults, card.recentResults);
  });
}
