import 'package:flutter/material.dart';

class Deck {
  final String id;
  final String name;
  final String courseId;

  static const generalId = 'general';
  static const fromTextsId = 'from_texts';
  static const alphabetId = 'alphabet';
  static const babelId = 'babel';

  const Deck({required this.id, required this.name, required this.courseId});

  bool get isGeneral => id == generalId;
  bool get isFromTexts => id == fromTextsId;
  bool get isAlphabet => id == alphabetId;
  bool get isBabel => id == babelId;
  bool get isVirtual => isGeneral || isFromTexts || isAlphabet || isBabel;

  Color get accentColor {
    if (isGeneral) return const Color(0xFF7C5CFC);
    if (isFromTexts) return const Color(0xFF26C6DA);
    if (isAlphabet) return const Color(0xFFFF7043);
    if (isBabel) return const Color(0xFFAB47BC);
    return const Color(0xFF4CAF50); // green for all user-created decks
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'courseId': courseId};

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: j['id'] as String,
        name: j['name'] as String,
        courseId: j['courseId'] as String,
      );

  factory Deck.general(String courseId) =>
      Deck(id: generalId, name: 'General', courseId: courseId);

  factory Deck.fromTexts(String courseId) =>
      Deck(id: fromTextsId, name: 'From Texts', courseId: courseId);

  factory Deck.alphabet(String courseId, String nativeName) =>
      Deck(id: alphabetId, name: nativeName, courseId: courseId);

  factory Deck.babel(String courseId) =>
      Deck(id: babelId, name: 'Babel', courseId: courseId);
}
