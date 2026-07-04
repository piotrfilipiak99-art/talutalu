import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/flashcard.dart';
import '../models/deck.dart';
import '../models/conversation.dart';
import '../models/explain_request.dart';
import '../theme/app_theme.dart';
import 'api_client.dart';

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
    ApiClient.instance.init(_p);
    _migrateTextIds();
    final storedDark = _p.getBool('darkMode') ?? true;
    AppColors.setDark(storedDark);
    darkMode.value = storedDark;
    // Pick up changes made on other devices; offline is fine — local wins
    // until the next successful sync.
    if (ApiClient.instance.hasSession) {
      unawaited(syncNow().catchError((_) {}));
    }
  }

  // ── Sync (offline-first, per-key last-write-wins) ───────────────────────────
  //
  // Every mutating method below calls _touch(key): the write always lands in
  // SharedPreferences first (the app never waits for the network), the key is
  // marked dirty with a wall-clock timestamp, and a debounced push sends dirty
  // keys to the backend. The server keeps whichever side is newer and returns
  // the merged state, which is applied back here.

  /// Keys whose SharedPreferences value is a JSON-encoded string.
  /// Flashcards, decks, texts and conversations are NOT here — they sync
  /// per item through /sync/<collection> (see _syncCollection below).
  static const _jsonKeys = {
    'bases', 'courses', 'activeCourse', 'deck_settings',
  };

  /// (endpoint path, pending-ops key, local storage key) per collection.
  static const _collections = [
    ('/sync/flashcards', 'card_ops', 'flashcards'),
    ('/sync/decks', 'deck_ops', 'decks'),
    ('/sync/texts', 'text_ops', 'texts'),
    ('/sync/conversations', 'conv_ops', 'conversations'),
  ];
  static const _boolKeys = {'darkMode', 'notificationsEnabled', 'reminderEnabled'};
  static const _intKeys = {'reminderHour', 'reminderMinute', 'selectedAvatar'};
  static const _stringKeys = {
    'userName', 'userHobby', 'appLanguage', 'selectedBase', 'nativeLanguage',
  };

  Timer? _syncDebounce;
  final syncError = ValueNotifier<String?>(null);

  Map<String, int> get _syncMeta {
    final raw = _p.getString('sync_meta');
    if (raw == null) return {};
    return Map<String, int>.from(jsonDecode(raw) as Map);
  }

  Set<String> get _dirtyKeys {
    final raw = _p.getString('sync_dirty');
    if (raw == null) return {};
    return Set<String>.from(jsonDecode(raw) as List);
  }

  void _touch(String key) {
    final meta = _syncMeta..[key] = DateTime.now().millisecondsSinceEpoch;
    _p.setString('sync_meta', jsonEncode(meta));
    _p.setString('sync_dirty', jsonEncode([..._dirtyKeys, key]));
    _scheduleSync();
  }

  void _scheduleSync() {
    if (!ApiClient.instance.hasSession) return; // offline-only until login
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 3), () {
      syncNow().catchError((_) {}); // pending changes survive for a retry
    });
  }

  // ── Per-item ops for flashcards/decks ──────────────────────────────────────
  //
  // Whole-list keys sync all-or-nothing, so two devices editing different
  // cards would clobber each other. Instead every list save is diffed
  // against the previous one and each changed/removed item becomes a
  // pending op ({id: {payload, updatedAt, deleted}}) pushed on next sync.

  Map<String, dynamic> _pendingOps(String opsKey) {
    final raw = _p.getString(opsKey);
    if (raw == null) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  void _recordListOps(String opsKey, String storageKey,
      List<Map<String, dynamic>> after) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawBefore = _p.getString(storageKey);
    final before = rawBefore == null
        ? <Map<String, dynamic>>[]
        : [
            for (final e in jsonDecode(rawBefore) as List)
              Map<String, dynamic>.from(e as Map),
          ];
    final ops = _pendingOps(opsKey);
    final beforeById = {
      for (final e in before)
        if (e['id'] is String) e['id'] as String: jsonEncode(e),
    };
    final afterIds = <String>{};
    for (final e in after) {
      final id = e['id'] as String?;
      if (id == null) continue; // pre-migration item; synced after restart
      afterIds.add(id);
      if (beforeById[id] != jsonEncode(e)) {
        ops[id] = {'payload': e, 'updatedAt': now, 'deleted': false};
      }
    }
    for (final id in beforeById.keys) {
      if (!afterIds.contains(id)) {
        ops[id] = {'payload': null, 'updatedAt': now, 'deleted': true};
      }
    }
    _p.setString(opsKey, jsonEncode(ops));
    _scheduleSync();
  }

  /// Push pending ops for one collection, then rebuild the local list from
  /// the server's merged state plus any ops recorded while the request was
  /// in flight (those stay pending for the next round).
  Future<bool> _syncCollection({
    required String path,
    required String opsKey,
    required String storageKey,
  }) async {
    final snapshot = _pendingOps(opsKey);
    final serverItems = await ApiClient.instance.syncItems(path, [
      for (final e in snapshot.entries)
        {'id': e.key, ...Map<String, dynamic>.from(e.value as Map)},
    ]);

    // Drop acknowledged ops; keep ones that changed mid-request.
    final ops = _pendingOps(opsKey);
    for (final e in snapshot.entries) {
      if (jsonEncode(ops[e.key]) == jsonEncode(e.value)) ops.remove(e.key);
    }

    final byId = <String, Map<String, dynamic>>{};
    for (final item in serverItems) {
      if (item['deleted'] == true) continue;
      byId[item['id'] as String] =
          Map<String, dynamic>.from(item['payload'] as Map);
    }
    for (final e in ops.entries) {
      final op = Map<String, dynamic>.from(e.value as Map);
      if (op['deleted'] == true) {
        byId.remove(e.key);
      } else {
        byId[e.key] = Map<String, dynamic>.from(op['payload'] as Map);
      }
    }

    final merged = jsonEncode(byId.values.toList());
    final changed = merged != _p.getString(storageKey);
    await _p.setString(storageKey, merged);
    await _p.setString(opsKey, jsonEncode(ops));
    return changed;
  }

  /// One-time seeding: data created before per-item sync existed (or while
  /// logged out) becomes a full set of upsert ops on the first sync.
  void _seedCollectionOps() {
    if (_p.getBool('rel_seeded_v2') ?? false) return;
    for (final (_, opsKey, storageKey) in _collections) {
      final raw = _p.getString(storageKey);
      if (raw == null) continue;
      final now = DateTime.now().millisecondsSinceEpoch;
      final ops = _pendingOps(opsKey);
      for (final e in jsonDecode(raw) as List) {
        final item = Map<String, dynamic>.from(e as Map);
        ops.putIfAbsent(item['id'] as String,
            () => {'payload': item, 'updatedAt': now, 'deleted': false});
      }
      _p.setString(opsKey, jsonEncode(ops));
    }
  }

  /// Texts created before per-item sync had no id — assign one so they can
  /// be addressed as sync items. Runs once per install at startup.
  void _migrateTextIds() {
    final raw = _p.getString('texts');
    if (raw == null) return;
    final list = [
      for (final e in jsonDecode(raw) as List)
        Map<String, dynamic>.from(e as Map),
    ];
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i]['id'] == null) {
        list[i]['id'] = 't${DateTime.now().microsecondsSinceEpoch}_$i';
        changed = true;
      }
    }
    if (changed) _p.setString('texts', jsonEncode(list));
  }

  Object? _readForPush(String key) {
    if (_jsonKeys.contains(key)) {
      final raw = _p.getString(key);
      return raw == null ? null : jsonDecode(raw);
    }
    if (_boolKeys.contains(key)) return _p.getBool(key);
    if (_intKeys.contains(key)) return _p.getInt(key);
    return _p.getString(key);
  }

  Future<void> _applyFromServer(String key, Object? value) async {
    if (_jsonKeys.contains(key)) {
      await _p.setString(key, jsonEncode(value));
    } else if (_boolKeys.contains(key) && value is bool) {
      await _p.setBool(key, value);
    } else if (_intKeys.contains(key) && value is int) {
      await _p.setInt(key, value);
    } else if (_stringKeys.contains(key) && value is String) {
      await _p.setString(key, value);
    }
  }

  /// Push dirty keys, pull the merged state, apply newer server values.
  Future<void> syncNow() async {
    if (!ApiClient.instance.hasSession) return;
    _seedCollectionOps();
    try {
      var cardsOrDecksChanged = false;
      for (final (path, opsKey, storageKey) in _collections) {
        final changed = await _syncCollection(
          path: path,
          opsKey: opsKey,
          storageKey: storageKey,
        );
        if (changed && (storageKey == 'flashcards' || storageKey == 'decks')) {
          cardsOrDecksChanged = true;
        }
      }
      await _p.setBool('rel_seeded_v2', true);
      if (cardsOrDecksChanged) flashcardsChanged.value++;
    } on ApiException catch (e) {
      syncError.value = e.message;
      rethrow;
    }
    final meta = _syncMeta;
    final push = <String, dynamic>{
      for (final key in _dirtyKeys)
        key: {'value': _readForPush(key), 'updatedAt': meta[key] ?? 0},
    };
    try {
      final serverState = await ApiClient.instance.sync(push);
      var changed = false;
      for (final entry in serverState.entries) {
        final item = Map<String, dynamic>.from(entry.value as Map);
        final serverAt = item['updatedAt'] as int;
        if (serverAt > (meta[entry.key] ?? 0)) {
          await _applyFromServer(entry.key, item['value']);
          meta[entry.key] = serverAt;
          changed = true;
        }
      }
      await _p.setString('sync_meta', jsonEncode(meta));
      await _p.setString('sync_dirty', jsonEncode(<String>[]));
      syncError.value = null;
      if (changed) {
        AppColors.setDark(_p.getBool('darkMode') ?? true);
        darkMode.value = _p.getBool('darkMode') ?? true;
        flashcardsChanged.value++;
        courseChanged.value++;
      }
    } on ApiException catch (e) {
      syncError.value = e.message;
      rethrow;
    }
  }

  Future<void> setDarkMode(bool value) async {
    await _p.setBool('darkMode', value);
    AppColors.setDark(value);
    darkMode.value = value;
    _touch('darkMode');
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
    _touch('userName');
    _touch('userHobby');
  }

  // ── Notifications ────────────────────────────────────────────────────────────
  // Persists preferences only — this does not yet schedule a real OS
  // notification (no platform plugin wired up), see notifications screen
  // for the user-facing caveat.

  bool get notificationsEnabled => _p.getBool('notificationsEnabled') ?? true;
  Future<void> setNotificationsEnabled(bool value) async {
    await _p.setBool('notificationsEnabled', value);
    _touch('notificationsEnabled');
  }

  bool get reminderEnabled => _p.getBool('reminderEnabled') ?? false;
  int get reminderHour => _p.getInt('reminderHour') ?? 19;
  int get reminderMinute => _p.getInt('reminderMinute') ?? 0;

  Future<void> saveReminder(
      {required bool enabled, required int hour, required int minute}) async {
    await _p.setBool('reminderEnabled', enabled);
    await _p.setInt('reminderHour', hour);
    await _p.setInt('reminderMinute', minute);
    _touch('reminderEnabled');
    _touch('reminderHour');
    _touch('reminderMinute');
  }

  // ── Native language (mother tongue, asked during onboarding) ───────────────

  String? get nativeLanguage => _p.getString('nativeLanguage');
  Future<void> setNativeLanguage(String code) async {
    await _p.setString('nativeLanguage', code);
    _touch('nativeLanguage');
  }

  // ── App language (UI language, not the learning target) ────────────────────

  String get appLanguage => _p.getString('appLanguage') ?? 'en';
  Future<void> setAppLanguage(String code) async {
    await _p.setString('appLanguage', code);
    _touch('appLanguage');
  }

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
    _touch('bases');
    _touch('courses');
    if (selectedBase != null) _touch('selectedBase');
    if (activeCourse != null) _touch('activeCourse');
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

  Future<void> saveTexts(List<Map<String, dynamic>> texts) async {
    _recordListOps('text_ops', 'texts', texts);
    await _p.setString('texts', jsonEncode(texts));
  }

  // ── Avatar ──────────────────────────────────────────────────────────────────

  int? get selectedAvatar => _p.containsKey('selectedAvatar')
      ? _p.getInt('selectedAvatar')
      : null;
  Future<void> saveAvatar(int index) async {
    await _p.setInt('selectedAvatar', index);
    _touch('selectedAvatar');
  }

  // ── Flashcards ──────────────────────────────────────────────────────────────

  List<Flashcard> get flashcards {
    final raw = _p.getString('flashcards');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Flashcard.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveFlashcards(List<Flashcard> cards) async {
    final maps = cards.map((c) => c.toJson()).toList();
    _recordListOps('card_ops', 'flashcards', maps);
    await _p.setString('flashcards', jsonEncode(maps));
  }

  List<Deck> get decks {
    final raw = _p.getString('decks');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Deck.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveDecks(List<Deck> decks) async {
    final maps = decks.map((d) => d.toJson()).toList();
    _recordListOps('deck_ops', 'decks', maps);
    await _p.setString('decks', jsonEncode(maps));
  }

  // ── Flashcards settings (per-deck map) ──────────────────────────────────────

  Map<String, dynamic> get deckSettings {
    final raw = _p.getString('deck_settings');
    if (raw == null) return {};
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> saveDeckSettings(Map<String, dynamic> s) async {
    await _p.setString('deck_settings', jsonEncode(s));
    _touch('deck_settings');
  }

  // ── Conversations (Converse) ────────────────────────────────────────────────

  List<Conversation> get conversations {
    final raw = _p.getString('conversations');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Conversation.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveConversations(List<Conversation> list) async {
    final maps = list.map((c) => c.toJson()).toList();
    _recordListOps('conv_ops', 'conversations', maps);
    await _p.setString('conversations', jsonEncode(maps));
  }

  // ── Clear ───────────────────────────────────────────────────────────────────

  Future<void> clearAll() async {
    _syncDebounce?.cancel();
    await _p.clear(); // also drops authToken — logging out ends the session
  }
}
