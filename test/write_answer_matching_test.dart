import 'package:flutter_test/flutter_test.dart';

import 'package:talutalu/screens/flashcards_screen.dart';

void main() {
  group('Write answer matching with multi-variant translations', () {
    const answer = 'over / above';

    test('single correct variant is enough', () {
      expect(matchesWriteAnswer('over', answer), isTrue);
      expect(matchesWriteAnswer('above', answer), isTrue);
      expect(matchesWriteAnswer('  Above ', answer), isTrue);
    });

    test('multiple variants accepted in any order and any separator style',
        () {
      expect(matchesWriteAnswer('over, above', answer), isTrue);
      expect(matchesWriteAnswer('above,over', answer), isTrue);
      expect(matchesWriteAnswer('above/over', answer), isTrue);
      expect(matchesWriteAnswer('over / above', answer), isTrue);
      expect(matchesWriteAnswer('above; over', answer), isTrue);
    });

    test('wrong or partially wrong input is rejected', () {
      expect(matchesWriteAnswer('under', answer), isFalse);
      expect(matchesWriteAnswer('over, under', answer), isFalse);
      expect(matchesWriteAnswer('', answer), isFalse);
      expect(matchesWriteAnswer(' / ', answer), isFalse);
    });

    test('stored answers with comma or semicolon separators work the same',
        () {
      expect(matchesWriteAnswer('true', 'real, true'), isTrue);
      expect(matchesWriteAnswer('to get', 'to receive; to get'), isTrue);
      expect(matchesWriteAnswer('to receive / to get', 'to receive; to get'),
          isTrue);
    });

    test('multi-word variants tolerate extra inner spaces', () {
      expect(matchesWriteAnswer('in  the   morning', 'in the morning'),
          isTrue);
    });
  });
}
