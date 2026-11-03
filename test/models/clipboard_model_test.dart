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

  ClipboardModel m({String? app, String? title}) => ClipboardModel(
    id: 1,
    content: 'x',
    createdAt: DateTime(2026),
    sourceApp: app,
    sourceTitle: title,
  );

  test('fromMap reads source and pinned', () {
    final c = ClipboardModel.fromMap({
      'id': 1,
      'content': 'x',
      'created_at': 0,
      'source_app': 'Google Chrome',
      'source_title': 'Inbox',
      'pinned': 1,
    });
    expect(c.sourceApp, 'Google Chrome');
    expect(c.sourceTitle, 'Inbox');
    expect(c.pinned, isTrue);
  });

  test('fromMap defaults when columns are null/0', () {
    final c = ClipboardModel.fromMap({
      'id': 1,
      'content': 'x',
      'created_at': 0,
      'source_app': null,
      'source_title': null,
      'pinned': 0,
    });
    expect(c.sourceApp, isNull);
    expect(c.sourceTitle, isNull);
    expect(c.pinned, isFalse);
  });

  test('sourceLabel formats app and title', () {
    expect(
      m(app: 'Google Chrome', title: 'Inbox - Gmail').sourceLabel,
      'Google Chrome — Inbox - Gmail',
    );
    expect(m(app: 'Google Chrome').sourceLabel, 'Google Chrome');
    expect(m(title: 'Orphan title').sourceLabel, isNull);
    expect(m().sourceLabel, isNull);
  });
}
