import 'package:clipps/models/clipboard_model.dart';
import 'package:clipps/models/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  final u = DateTime.fromMillisecondsSinceEpoch(1700000060000);

  test('Note.fromMap reads every column', () {
    final n = Note.fromMap({
      'id': 3,
      'clip_id': 9,
      'body': 'hi',
      'created_at': 1700000000000,
      'updated_at': 1700000060000,
    });
    expect(n.id, 3);
    expect(n.clipId, 9);
    expect(n.body, 'hi');
    expect(n.createdAt, t);
    expect(n.updatedAt, u);
  });

  test('edited is false when updatedAt equals createdAt, true otherwise', () {
    Note n(DateTime up) =>
        Note(id: 1, clipId: 1, body: 'b', createdAt: t, updatedAt: up);
    expect(n(t).edited, isFalse);
    expect(n(u).edited, isTrue);
  });

  test('NoteEntry and Note compare by value', () {
    Note n() => Note(id: 1, clipId: 1, body: 'b', createdAt: t, updatedAt: t);
    final c = ClipboardModel(id: 1, content: 'x', createdAt: t);
    expect(n(), n());
    expect(n().hashCode, n().hashCode);
    expect(
      n() ==
          Note.fromMap({
            'id': 2,
            'clip_id': 1,
            'body': 'b',
            'created_at': t.millisecondsSinceEpoch,
            'updated_at': t.millisecondsSinceEpoch,
          }),
      isFalse,
    );
    expect(
      NoteEntry(note: n(), clip: c) == NoteEntry(note: n(), clip: c),
      isTrue,
    );
  });
}
