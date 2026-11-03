import 'package:characters/characters.dart';

class ClipboardModel {
  final int id;
  final String content;
  final DateTime createdAt;
  final String? sourceApp;
  final String? sourceTitle;
  final bool pinned;

  const ClipboardModel({
    required this.id,
    required this.content,
    required this.createdAt,
    this.sourceApp,
    this.sourceTitle,
    this.pinned = false,
  });

  factory ClipboardModel.fromMap(Map<String, Object?> map) => ClipboardModel(
    id: map['id'] as int,
    content: map['content'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    sourceApp: map['source_app'] as String?,
    sourceTitle: map['source_title'] as String?,
    pinned: map['pinned'] == 1,
  );

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
