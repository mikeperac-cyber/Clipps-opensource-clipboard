import 'package:characters/characters.dart';

class ClipboardModel {
  final int id;
  final String content;
  final DateTime createdAt;

  const ClipboardModel({
    required this.id,
    required this.content,
    required this.createdAt,
  });

  factory ClipboardModel.fromMap(Map<String, Object?> map) => ClipboardModel(
    id: map['id'] as int,
    content: map['content'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );

  /// First 500 grapheme clusters, so emoji are never split.
  String get preview => content.characters.take(500).toString();
}
