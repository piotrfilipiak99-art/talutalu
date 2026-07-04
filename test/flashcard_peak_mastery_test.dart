import 'package:flutter_test/flutter_test.dart';
import 'package:talutalu/models/flashcard.dart';

void main() {
  test(
      'peakMasteryLevel keeps the highest level a card ever reached even '
      'after the live masteryLevel drops back down from wrong answers', () {
    final card = Flashcard(
      id: '1',
      word: 'test',
      translation: 'test',
      courseId: 'en_pl',
    );

    for (var i = 0; i < 10; i++) {
      card.applyEasy();
    }
    expect(card.masteryLevel, 10);
    expect(card.peakMasteryLevel, 10);

    card.applyAgain();
    expect(card.masteryLevel, 9); // dropped from a wrong answer
    expect(card.peakMasteryLevel, 10); // but the peak isn't taken back
  });

  test(
      'a wrong answer never raises masteryLevel — the exact bug report: '
      '5 correct -> level 5, then a 6th wrong answer must not push it to 6',
      () {
    final card = Flashcard(
      id: '2',
      word: 'test2',
      translation: 'test2',
      courseId: 'en_pl',
    );

    for (var i = 0; i < 5; i++) {
      card.applyEasy();
    }
    expect(card.masteryLevel, 5);

    card.applyAgain();
    expect(card.masteryLevel, 4);
  });
}
