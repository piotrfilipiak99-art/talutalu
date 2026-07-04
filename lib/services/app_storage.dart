import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard.dart';
import '../models/deck.dart';
import '../models/conversation.dart';
import '../models/explain_request.dart';
import '../theme/app_theme.dart';

/// Single source of truth for local persistence.
/// All methods are synchronous after [init] is called in main().
/// Swap the implementation (SharedPreferences → HTTP) here without touching screens.
class AppStorage {
  AppStorage._();
  static final instance = AppStorage._();

  late SharedPreferences _p;

  /// Incremented whenever flashcards are saved by an external source
  /// (e.g. Read screen). FlashcardsScreen listens to reload its state.
  final flashcardsChanged = ValueNotifier<int>(0);
  final courseChanged = ValueNotifier<int>(0);
  final hideAlphabetPanel = ValueNotifier<bool>(false);

  /// Set by the Read tab when the user asks to discuss a selected sentence
  /// in Converse. HomeScreen listens to switch to the Converse tab;
  /// ConverseScreen listens to open a new conversation around it, then
  /// resets it to null. In-memory only — never persisted.
  final explainRequest = ValueNotifier<ExplainRequest?>(null);

  /// Holds the current value directly (like [hideAlphabetPanel]) — screens
  /// that need to repaint on a theme flip listen to this.
  final darkMode = ValueNotifier<bool>(true);

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final storedDark = _p.getBool('darkMode') ?? true;
    AppColors.setDark(storedDark);
    darkMode.value = storedDark;
  }

  Future<void> setDarkMode(bool value) async {
    await _p.setBool('darkMode', value);
    AppColors.setDark(value);
    darkMode.value = value;
  }

  // ── Auth ────────────────────────────────────────────────────────────────────

  bool get isLoggedIn => _p.getBool('isLoggedIn') ?? false;
  Future<void> setLoggedIn(bool v) => _p.setBool('isLoggedIn', v);

  // ── Profile ─────────────────────────────────────────────────────────────────

  String get userName => _p.getString('userName') ?? '';
  String get userHobby => _p.getString('userHobby') ?? '';

  Future<void> saveProfile(String name, String hobby) async {
    await _p.setString('userName', name);
    await _p.setString('userHobby', hobby);
  }

  // ── Notifications ────────────────────────────────────────────────────────────
  // Persists preferences only — this does not yet schedule a real OS
  // notification (no platform plugin wired up), see notifications screen
  // for the user-facing caveat.

  bool get notificationsEnabled => _p.getBool('notificationsEnabled') ?? true;
  Future<void> setNotificationsEnabled(bool value) =>
      _p.setBool('notificationsEnabled', value);

  bool get reminderEnabled => _p.getBool('reminderEnabled') ?? false;
  int get reminderHour => _p.getInt('reminderHour') ?? 19;
  int get reminderMinute => _p.getInt('reminderMinute') ?? 0;

  Future<void> saveReminder(
      {required bool enabled, required int hour, required int minute}) async {
    await _p.setBool('reminderEnabled', enabled);
    await _p.setInt('reminderHour', hour);
    await _p.setInt('reminderMinute', minute);
  }

  // ── App language (UI language, not the learning target) ────────────────────

  String get appLanguage => _p.getString('appLanguage') ?? 'en';
  Future<void> setAppLanguage(String code) => _p.setString('appLanguage', code);

  // ── Courses ─────────────────────────────────────────────────────────────────

  List<Map<String, String>> get bases {
    final raw = _p.getString('bases');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  List<Map<String, String>> get courses {
    final raw = _p.getString('courses');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  String? get selectedBase => _p.getString('selectedBase');

  Map<String, String>? get activeCourse {
    final raw = _p.getString('activeCourse');
    if (raw == null) return null;
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> saveCourseState({
    required List<Map<String, String>> bases,
    required List<Map<String, String>> courses,
    String? selectedBase,
    Map<String, String>? activeCourse,
  }) async {
    await _p.setString('bases', jsonEncode(bases));
    await _p.setString('courses', jsonEncode(courses));
    if (selectedBase != null) await _p.setString('selectedBase', selectedBase);
    if (activeCourse != null) {
      await _p.setString('activeCourse', jsonEncode(activeCourse));
    }
    courseChanged.value++;
  }

  // ── Texts ───────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get texts {
    final raw = _p.getString('texts');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> saveTexts(List<Map<String, dynamic>> texts) =>
      _p.setString('texts', jsonEncode(texts));

  // ── Avatar ──────────────────────────────────────────────────────────────────

  int? get selectedAvatar => _p.containsKey('selectedAvatar')
      ? _p.getInt('selectedAvatar')
      : null;
  Future<void> saveAvatar(int index) => _p.setInt('selectedAvatar', index);

  // ── Flashcards ──────────────────────────────────────────────────────────────

  List<Flashcard> get flashcards {
    final raw = _p.getString('flashcards');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Flashcard.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveFlashcards(List<Flashcard> cards) =>
      _p.setString('flashcards', jsonEncode(cards.map((c) => c.toJson()).toList()));

  List<Deck> get decks {
    final raw = _p.getString('decks');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Deck.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveDecks(List<Deck> decks) =>
      _p.setString('decks', jsonEncode(decks.map((d) => d.toJson()).toList()));

  // ── Flashcards settings (per-deck map) ──────────────────────────────────────

  Map<String, dynamic> get deckSettings {
    final raw = _p.getString('deck_settings');
    if (raw == null) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> saveDeckSettings(Map<String, dynamic> s) =>
      _p.setString('deck_settings', jsonEncode(s));

  // ── Conversations (Converse) ────────────────────────────────────────────────

  List<Conversation> get conversations {
    final raw = _p.getString('conversations');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveConversations(List<Conversation> list) => _p.setString(
      'conversations', jsonEncode(list.map((c) => c.toJson()).toList()));

  // ── Clear ───────────────────────────────────────────────────────────────────

  Future<void> clearAll() => _p.clear();
}
