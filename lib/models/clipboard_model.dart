import 'package:characters/characters.dart';

import '../services/auto_tagger.dart';

enum TaskState { none, open, done }

class ClipboardModel {
  final int id;
  final String content;
  final DateTime createdAt;
  final String? sourceApp;
  final String? sourceTitle;
  final bool pinned;
  final DateTime? deletedAt;
  final TaskState taskState;
  final int? groupId;

  /// Auto tags in [kAutoTags] order, then manual tags A-Z.
  final List<String> tags;

  final int noteCount;

  const ClipboardModel({
    required this.id,
    required this.content,
    required this.createdAt,
    this.sourceApp,
    this.sourceTitle,
    this.pinned = false,
    this.deletedAt,
    this.taskState = TaskState.none,
    this.groupId,
    this.tags = const [],
    this.noteCount = 0,
  });

  factory ClipboardModel.fromMap(Map<String, Object?> map) => ClipboardModel(
    id: map['id'] as int,
    content: map['content'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    sourceApp: map['source_app'] as String?,
    sourceTitle: map['source_title'] as String?,
    pinned: map['pinned'] == 1,
    deletedAt: switch (map['deleted_at']) {
      final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
      _ => null,
    },
    taskState: switch (map['task_state']) {
      0 => TaskState.open,
      1 => TaskState.done,
      _ => TaskState.none,
    },
    groupId: map['group_id'] as int?,
    tags: _sortTags(map['tags'] as String?),
    noteCount: map['note_count'] as int? ?? 0,
  );

  static List<String> _sortTags(String? joined) {
    if (joined == null || joined.isEmpty) return const [];
    int rank(String t) {
      final i = kAutoTags.indexWhere((a) => a.toLowerCase() == t.toLowerCase());
      return i < 0 ? kAutoTags.length : i;
    }

    return joined.split('\u001F')..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.toLowerCase().compareTo(b.toLowerCase());
    });
  }

  bool get isSecret => tags.any((t) => t.toLowerCase() == 'secret');

  /// 'App — Title', 'App', or null (a title alone is not shown).
  String? get sourceLabel {
    final app = sourceApp;
    if (app == null) return null;
    final title = sourceTitle;
    return title == null ? app : '$app — $title';
  }

  /// First 500 grapheme clusters, so emoji are never split.
  String get preview => content.characters.take(500).toString();
}
