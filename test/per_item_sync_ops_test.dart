import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:talutalu/models/flashcard.dart';
import 'package:talutalu/services/app_storage.dart';

Flashcard _card(String id, String word) => Flashcard(
      id: id,
      word: word,
      translation: 'tr-$word',
      courseId: 'c1',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> readOps() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('card_ops');
    return raw == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  test(
      'saving flashcard lists records per-item ops: only changed cards become '
      'upserts and removed cards become tombstone deletes', () async {
    SharedPreferences.setMockInitialValues({});
    await AppStorage.instance.init();
    final storage = AppStorage.instance;

    // First save: both cards are new -> two upsert ops.
    final kot = _card('id-kot', 'kot');
    final pies = _card('id-pies', 'pies');
    await storage.saveFlashcards([kot, pies]);
    var ops = await readOps();
    expect(ops.keys, containsAll(['id-kot', 'id-pies']));
    expect(ops['id-kot']['deleted'], false);

    // Editing one card only touches that card's op.
    final opsBefore = await readOps();
    kot.translation = 'cat (updated)';
    await storage.saveFlashcards([kot, pies]);
    ops = await readOps();
    expect(ops['id-kot']['payload']['translation'], 'cat (updated)');
    expect(jsonEncode(ops['id-pies']), jsonEncode(opsBefore['id-pies']),
        reason: 'untouched card must not get a fresh op/timestamp');

    // Removing a card records a tombstone, not silence.
    await storage.saveFlashcards([kot]);
    ops = await readOps();
    expect(ops['id-pies']['deleted'], true);
    expect(ops['id-pies']['payload'], isNull);

    // The local list itself still round-trips normally.
    final stored = storage.flashcards;
    expect(stored.length, 1);
    expect(stored.single.translation, 'cat (updated)');
  });
}
