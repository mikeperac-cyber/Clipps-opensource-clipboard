import 'dart:async';

import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../models/clip_group.dart';
import '../models/clip_source.dart';
import '../models/clip_view.dart';
import '../models/clipboard_model.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseException;

const kTrashRetention = Duration(days: 15);

class ClipboardProvider extends ChangeNotifier {
  ClipboardProvider(this._db, {this._clock = DateTime.now});

  final DbHelper _db;
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
  List<String> _tagsInUse = [];
  Timer? _retentionTimer;

  ClipView get view => _view;
  int? get groupId => _groupId;
  String? get tagFilter => _tagFilter;
  List<ClipGroup> get groups => _groups;
  List<String> get tagsInUse => _tagsInUse;

  List<ClipboardModel> get clips => _clips;
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
    await _reload();
    notifyListeners();
  }

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
    await _db.trashClips(_selectedIds, _clock());
    _selectedIds.clear();
    await load();
  }

  Future<void> trashClip(int id) async {
    await _db.trashClips([id], _clock());
    _selectedIds.remove(id);
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
