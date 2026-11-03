import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../models/clip_source.dart';
import '../models/clipboard_model.dart';

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
    );
  }

  Future<void> load() async {
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

  Future<void> deleteSelected() async {
    await _db.deleteClips(_selectedIds);
    _selectedIds.clear();
    await load();
  }

  Future<void> deleteClip(int id) async {
    await _db.deleteClips([id]);
    _selectedIds.remove(id);
    await load();
  }
}
