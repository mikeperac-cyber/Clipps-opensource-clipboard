import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/db_helper.dart';
import '../models/clip_group.dart';
import '../models/clip_source.dart';
import '../models/clip_view.dart';
import '../models/clipboard_model.dart';
import '../models/note.dart';
import '../services/csv_export.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseException;

const kTrashRetention = Duration(days: 15);

enum NoteResult { saved, blank, tooLong, missing }

ThemeMode themeFromSetting(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class ClipboardProvider extends ChangeNotifier {
  ClipboardProvider(this._db, {this._clock = DateTime.now});

  final DbHelper _db;

  String get dataDir => p.dirname(_db.path);
  final DateTime Function() _clock;

  List<ClipboardModel> _clips = [];
  String _searchText = '';
  DateTimeRange? _dateRange;
  final Set<int> _selectedIds = {};
  // Serializes addClip so each dedupe check sees the previous insert.
  Future<void> _addQueue = Future.value();
  int _searchFocusRequests = 0;
  bool _hotkeyUnavailable = false;
  ClipView _view = ClipView.all;
  int? _groupId;
  String? _tagFilter;
  List<ClipGroup> _groups = [];
  Set<int> _duplicateIds = {};
  List<String> _tagsInUse = [];
  Timer? _retentionTimer;
  List<NoteEntry> _notes = [];
  ThemeMode _themeMode = ThemeMode.system;
  bool _capturePaused = false;

  DateTime now() => _clock();

  bool isDuplicate(int id) => _duplicateIds.contains(id);

  ClipView get view => _view;
  int? get groupId => _groupId;
  String? get tagFilter => _tagFilter;
  List<ClipGroup> get groups => _groups;
  List<String> get tagsInUse => _tagsInUse;

  List<ClipboardModel> get clips => _clips;
  List<NoteEntry> get notes => _notes;
  ThemeMode get themeMode => _themeMode;
  bool get capturePaused => _capturePaused;
  String get searchText => _searchText;
  DateTimeRange? get dateRange => _dateRange;
  Set<int> get selectedIds => Set.unmodifiable(_selectedIds);
  int get searchFocusRequests => _searchFocusRequests;
  bool get hotkeyUnavailable => _hotkeyUnavailable;

  void requestSearchFocus() {
    _searchFocusRequests++;
    notifyListeners();
  }

  void markHotkeyUnavailable() {
    _hotkeyUnavailable = true;
    notifyListeners();
  }

  Future<void> togglePin(int id) async {
    final i = _clips.indexWhere((c) => c.id == id);
    if (i < 0) return;
    await _db.setPinned(id, !_clips[i].pinned);
    _selectedIds.remove(id);
    await load();
  }

  Future<void> _reload() async {
    if (_view == ClipView.notes) {
      _clips = [];
      _notes = await _db.notesView();
      _groups = await _db.listGroups();
      _tagsInUse = await _db.tagsInUse();
      return;
    }
    _notes = [];
    final r = _dateRange;
    _clips = await _db.getClips(
      text: _searchText,
      from: r == null
          ? null
          : DateTime(r.start.year, r.start.month, r.start.day),
      before: r == null
          ? null
          : DateTime(r.end.year, r.end.month, r.end.day + 1),
      view: _view,
      groupId: _groupId,
      tag: _tagFilter,
    );
    _groups = await _db.listGroups();
    _tagsInUse = await _db.tagsInUse();
    _duplicateIds = await _db.duplicateIds();
    final f = _tagFilter;
    if (f != null &&
        !_tagsInUse.any((t) => t.toLowerCase() == f.toLowerCase())) {
      _tagFilter = null; // the tag is gone; don't strand the user on a filter
      await _reload();
    }
  }

  Future<int> purgeExpiredTrash() async {
    final n = await _db.purgeTrashedBefore(_clock().subtract(kTrashRetention));
    if (n > 0) await load();
    return n;
  }

  void startRetentionTimer() {
    _retentionTimer?.cancel();
    _retentionTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => purgeExpiredTrash(),
    );
  }

  @override
  void dispose() {
    _retentionTimer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    await _db.purgeTrashedBefore(_clock().subtract(kTrashRetention));
    _themeMode = themeFromSetting(await _db.getSetting('theme'));
    _capturePaused = await _db.getSetting('capture_paused') == 'true';
    await _reload();
    notifyListeners();
  }

  Future<String> exportClips() async {
    final dir = await getDownloadsDirectory() ?? Directory(dataDir);
    return exportClipsCsv(
      _db,
      {for (final g in _groups) g.id: g.name},
      dir,
      _clock(),
    );
  }

  Future<void> setCapturePaused(bool paused) async {
    await _db.setSetting('capture_paused', paused ? 'true' : 'false');
    _capturePaused = paused;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _db.setSetting('theme', mode.name);
    _themeMode = mode;
    notifyListeners();
  }

  Future<List<Note>> notesFor(int clipId) => _db.notesForClip(clipId);

  static NoteResult? _noteError(String body) {
    if (body.trim().isEmpty) return NoteResult.blank;
    if (body.length > kMaxNoteLength) return NoteResult.tooLong;
    return null;
  }

  Future<NoteResult> addNote(int clipId, String body) async {
    final err = _noteError(body);
    if (err != null) return err;
    try {
      await _db.addNote(clipId, body, _clock());
    } on DatabaseException catch (e) {
      // 787 = SQLITE_CONSTRAINT_FOREIGNKEY: the clip was purged meanwhile.
      // Anything else (disk, lock, I/O) must reach the caller.
      if (e.getResultCode() != 787) rethrow;
      await load();
      return NoteResult.missing;
    }
    await load();
    return NoteResult.saved;
  }

  Future<NoteResult> editNote(int id, String body) async {
    final err = _noteError(body);
    if (err != null) return err;
    final ok = await _db.updateNote(id, body, _clock());
    await load();
    return ok ? NoteResult.saved : NoteResult.missing;
  }

  Future<void> deleteNote(int id) => _mutate(() => _db.deleteNote(id));

  Future<bool> addClip(
    String content, {
    ClipSource source = const ClipSource(),
  }) {
    final result = _addQueue.then((_) => _add(content, source));
    _addQueue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<bool> _add(String content, ClipSource source) async {
    if (content.trim().isEmpty) return false;
    if ((await _db.latestClip())?.content == content) return false;
    await _db.insertClip(content, _clock(), source: source);
    await load();
    return true;
  }

  Future<void> setSearchText(String text) async {
    _searchText = text;
    _selectedIds.clear();
    await load();
  }

  Future<void> setDateRange(DateTimeRange? range) async {
    _dateRange = range;
    _selectedIds.clear();
    await load();
  }

  void toggleSelected(int id) {
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
    notifyListeners();
  }

  /// Selects every clip in the list that can be acted on in bulk. Pinned clips
  /// cannot be trashed, so they are left out.
  void selectAllVisible() {
    _selectedIds
      ..clear()
      ..addAll(_clips.where((c) => !c.pinned).map((c) => c.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  Future<void> setView(ClipView v) async {
    _view = v;
    _groupId = null;
    _selectedIds.clear();
    await load();
  }

  Future<void> selectGroup(int id) async {
    _view = ClipView.all;
    _groupId = id;
    _selectedIds.clear();
    await load();
  }

  Future<void> setTagFilter(String? tag) async {
    _tagFilter = tag;
    _selectedIds.clear();
    await load();
  }

  Future<void> trashSelected() async {
    await _db.trashClips(_selectedIds.toList(), _clock());
    _selectedIds.clear();
    await load();
  }

  Future<void> trashClip(int id) async {
    await _db.trashClips([id], _clock());
    _selectedIds.remove(id);
    await load();
  }

  Future<void> restoreSelected() async {
    await _db.restoreClips(_selectedIds.toList());
    _selectedIds.clear();
    await load();
  }

  Future<void> restoreClip(int id) async {
    await _db.restoreClips([id]);
    _selectedIds.remove(id);
    await load();
  }

  Future<void> _mutate(Future<void> Function() f) async {
    await f();
    await load();
  }

  Future<void> makeTask(int id) =>
      _mutate(() => _db.setTaskState(id, TaskState.open));
  Future<void> setTaskDone(int id, bool done) => _mutate(
    () => _db.setTaskState(id, done ? TaskState.done : TaskState.open),
  );
  Future<void> removeTask(int id) =>
      _mutate(() => _db.setTaskState(id, TaskState.none));

  // Trims; null when empty, too long, or has a control character.
  static String? _clean(String raw, int max) {
    final t = raw.trim();
    if (t.isEmpty || t.length > max || t.codeUnits.any((c) => c < 0x20)) {
      return null;
    }
    return t;
  }

  Future<bool> _tryName(String name, Future<void> Function(String) f) async {
    final n = _clean(name, 40);
    if (n == null) return false;
    try {
      await f(n);
    } on DatabaseException {
      return false;
    }
    await load();
    return true;
  }

  Future<bool> createGroup(String name) =>
      _tryName(name, (n) => _db.createGroup(n));

  Future<bool> renameGroup(int id, String name) =>
      _tryName(name, (n) => _db.renameGroup(id, n));

  Future<void> deleteGroup(int id) async {
    await _db.deleteGroup(id);
    if (_groupId == id) _groupId = null;
    await load();
  }

  Future<void> setClipGroup(int clipId, int? groupId) =>
      _mutate(() => _db.setClipGroup(clipId, groupId));

  Future<bool> addTag(int clipId, String tag) async {
    final t = _clean(tag, 30);
    if (t == null) return false;
    await _db.addTag(clipId, t);
    await load();
    return true;
  }

  Future<void> removeTag(int clipId, String tag) =>
      _mutate(() => _db.removeTag(clipId, tag));
}
