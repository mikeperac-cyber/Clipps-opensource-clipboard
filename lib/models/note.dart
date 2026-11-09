import 'clipboard_model.dart';

/// Enforced by the provider, not the DB layer.
const kMaxNoteLength = 20000;

class Note {
  const Note({
    required this.id,
    required this.clipId,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int clipId;
  final String body;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get edited => updatedAt != createdAt;

  factory Note.fromMap(Map<String, Object?> map) => Note(
    id: map['id'] as int,
    clipId: map['clip_id'] as int,
    body: map['body'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
  );

  @override
  bool operator ==(Object other) =>
      other is Note &&
      other.id == id &&
      other.clipId == clipId &&
      other.body == body &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, clipId, body, createdAt, updatedAt);
}

class NoteEntry {
  const NoteEntry({required this.note, required this.clip});

  final Note note;
  final ClipboardModel clip;

  @override
  bool operator ==(Object other) =>
      other is NoteEntry && other.note == note && other.clip == clip;

  @override
  int get hashCode => Object.hash(note, clip);
}
