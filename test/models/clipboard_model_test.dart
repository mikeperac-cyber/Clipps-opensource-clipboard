import 'package:characters/characters.dart';
import 'package:clipps/models/clipboard_model.dart';
import 'package:flutter_test/flutter_test.dart';

ClipboardModel _clip(String c) =>
    ClipboardModel(id: 1, content: c, createdAt: DateTime(2026));

void main() {
  test('fromMap reads id, content and millisecond timestamp', () {
    final m = ClipboardModel.fromMap({
      'id': 7,
      'content': 'hi',
      'created_at': 1700000000000,
    });
    expect(m.id, 7);
    expect(m.content, 'hi');
    expect(m.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
  });

  test('preview keeps short content as-is', () {
    expect(_clip('short').preview, 'short');
  });

  test(
    'preview cuts long content to 500 characters without splitting emoji',
    () {
      final m = _clip('a' * 499 + '👍🏽' * 10);
      expect(m.preview.characters.length, 500);
      expect(m.preview.endsWith('👍🏽'), isTrue);
    },
  );
}
