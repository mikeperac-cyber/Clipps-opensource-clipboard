import 'dart:io';

import 'package:clipps/database/db_helper.dart';
import 'package:clipps/models/clip_source.dart';
import 'package:clipps/models/clip_view.dart';
import 'package:clipps/models/clipboard_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper db;
  setUp(() async {
    db = await DbHelper.open(databaseFactoryFfi, inMemoryDatabasePath);
  });
  tearDown(() => db.close());

  Future<List<String>> texts(String q) async => [
    for (final c in await db.getClips(text: q)) c.content,
  ];

  test('secure_delete is on after open', () async {
    final r = await db.rawDb.rawQuery('PRAGMA secure_delete');
    expect(r.first.values.first, 1);
  });

  test('insertClip returns the stored clip with an id', () async {
    final t = DateTime(2026, 1, 1, 10);
    final c = await db.insertClip('hello', t);
    expect(c.id, greaterThan(0));
    expect(c.content, 'hello');
    expect(c.createdAt, t);
  });

  test('getClips returns newest first, id breaks ties', () async {
    final t1 = DateTime(2026, 1, 1, 1);
    final t2 = DateTime(2026, 1, 1, 2);
    final t3 = DateTime(2026, 1, 1, 3);
    final a = await db.insertClip('t1', t1);
    final b = await db.insertClip('t3a', t3);
    final c = await db.insertClip('t2', t2);
    final d = await db.insertClip('t3b', t3);
    final got = await db.getClips();
    expect(got.map((e) => e.id), [d.id, b.id, c.id, a.id]);
  });

  test('latestClip is null when empty and newest otherwise', () async {
    expect(await db.latestClip(), isNull);
    await db.insertClip('old', DateTime(2026, 1, 1));
    await db.insertClip('new', DateTime(2026, 1, 2));
    expect((await db.latestClip())!.content, 'new');
  });

  test('getClips text filter is case-insensitive substring', () async {
    await db.insertClip('Hello World', DateTime(2026));
    await db.insertClip('other', DateTime(2026));
    expect(await texts('world'), ['Hello World']);
  });

  test(r'getClips treats % _ and \ literally', () async {
    for (final s in [
      '50% off',
      '50 off',
      'snake_case',
      'snakeXcase',
      r'a\b',
      'ab',
    ]) {
      await db.insertClip(s, DateTime(2026));
    }
    expect(await texts('%'), ['50% off']);
    expect(await texts('_'), ['snake_case']);
    expect(await texts(r'\'), [r'a\b']);
  });

  test('getClips from is inclusive and before is exclusive', () async {
    final t10 = DateTime(2026, 1, 1, 10);
    final t11 = DateTime(2026, 1, 1, 11);
    final t12 = DateTime(2026, 1, 1, 12);
    await db.insertClip('10', t10);
    await db.insertClip('11', t11);
    await db.insertClip('12', t12);
    final got = await db.getClips(from: t11, before: t12);
    expect(got.map((e) => e.content), ['11']);
  });

  test('deleteClips removes only the given ids and returns count', () async {
    final a = await db.insertClip('a', DateTime(2026));
    final b = await db.insertClip('b', DateTime(2026));
    final c = await db.insertClip('c', DateTime(2026));
    expect(await db.deleteClips([a.id, b.id]), 2);
    expect((await db.getClips()).map((e) => e.id), [c.id]);
  });

  test('deleteClips with no ids returns 0', () async {
    await db.insertClip('a', DateTime(2026));
    expect(await db.deleteClips([]), 0);
    expect(await db.getClips(), hasLength(1));
  });

  test('stores 5 MB of text intact', () async {
    final big = 'x' * 5 * 1024 * 1024;
    final c = await db.insertClip(big, DateTime(2026));
    final got = (await db.getClips()).single;
    expect(got.id, c.id);
    expect(got.content.length, big.length);
  });

  test('insertClip stores source', () async {
    final t = DateTime(2026, 1, 1);
    await db.insertClip(
      'a',
      t,
      source: const ClipSource(app: 'A', title: 'T'),
    );
    final c = (await db.getClips()).single;
    expect(c.sourceApp, 'A');
    expect(c.sourceTitle, 'T');
  });

  test('empty source strings are stored as NULL', () async {
    final c = await db.insertClip(
      'a',
      DateTime(2026),
      source: const ClipSource(app: '', title: ''),
    );
    expect(c.sourceApp, isNull);
    final row = (await db.rawDb.query('clips')).single;
    expect(row['source_app'], isNull);
    expect(row['source_title'], isNull);
  });

  test('setPinned pins and unpins', () async {
    final c = await db.insertClip('a', DateTime(2026));
    await db.setPinned(c.id, true);
    expect((await db.getClips()).single.pinned, isTrue);
    await db.setPinned(c.id, false);
    expect((await db.getClips()).single.pinned, isFalse);
  });

  test('pinned clips sort first, newest pinned first, obey filters', () async {
    final oldest = await db.insertClip('apple 1', DateTime(2026, 1, 1));
    final older = await db.insertClip('apple 2', DateTime(2026, 1, 2));
    final newest = await db.insertClip('apple 3', DateTime(2026, 1, 3));
    await db.setPinned(oldest.id, true);
    await db.setPinned(older.id, true);
    expect((await db.getClips()).map((e) => e.id), [
      older.id,
      oldest.id,
      newest.id,
    ]);
    expect(await texts('3'), ['apple 3']);
  });

  test('latestClip ignores pins', () async {
    final old = await db.insertClip('old', DateTime(2026, 1, 1));
    final newer = await db.insertClip('new', DateTime(2026, 1, 2));
    await db.setPinned(old.id, true);
    expect((await db.latestClip())!.id, newer.id);
  });

  test('deleteClips never removes pinned rows', () async {
    final p = await db.insertClip('p', DateTime(2026, 1, 1));
    final n = await db.insertClip('n', DateTime(2026, 1, 2));
    await db.setPinned(p.id, true);
    expect(await db.deleteClips([p.id, n.id]), 1);
    expect((await db.getClips()).single.id, p.id);
  });

  test('upgrade from v1 keeps rows', () async {
    final dir = await Directory.systemTemp.createTemp('clipps_v1');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/c.db';
    final v1 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE clips('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'content TEXT NOT NULL, '
            'created_at INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX idx_clips_created_at ON clips(created_at)',
          );
        },
      ),
    );
    await v1.insert('clips', {'content': 'one', 'created_at': 1});
    await v1.insert('clips', {'content': 'two', 'created_at': 2});
    await v1.close();

    final up = await DbHelper.open(databaseFactoryFfi, path);
    addTearDown(up.close);
    final got = await up.getClips();
    expect(got.map((c) => c.content), ['two', 'one']);
    expect(got.every((c) => !c.pinned), isTrue);
    expect(
      got.every((c) => c.sourceApp == null && c.sourceTitle == null),
      isTrue,
    );
    final c = await up.insertClip(
      'three',
      DateTime.fromMillisecondsSinceEpoch(3),
      source: const ClipSource(app: 'A'),
    );
    expect(c.sourceApp, 'A');
  });

  test('insertClip stores auto tags', () async {
    final c = await db.insertClip('https://x.io', DateTime(2026));
    expect(c.tags, ['Link']);
    expect((await db.getClips()).single.tags, ['Link']);
    expect((await db.insertClip('plain', DateTime(2026))).tags, isEmpty);
  });

  test('latestClip ignores trashed clips', () async {
    final old = await db.insertClip('old', DateTime(2026, 1, 1));
    final n = await db.insertClip('new', DateTime(2026, 1, 2));
    await db.rawDb.update(
      'clips',
      {'deleted_at': 1},
      where: 'id = ?',
      whereArgs: [n.id],
    );
    expect((await db.latestClip())!.id, old.id);
  });

  test('getClips views: all excludes trash, tasks orders open first, '
      'trash orders by deleted_at', () async {
    final a = await db.insertClip('a', DateTime(2026, 1, 1));
    final b = await db.insertClip('b', DateTime(2026, 1, 2));
    final c = await db.insertClip('c', DateTime(2026, 1, 3));
    final d = await db.insertClip('d', DateTime(2026, 1, 4));
    Future<void> set(int id, Map<String, Object?> v) =>
        db.rawDb.update('clips', v, where: 'id = ?', whereArgs: [id]);
    await set(a.id, {'task_state': 1});
    await set(b.id, {'task_state': 0});
    await set(c.id, {'task_state': 0});
    await set(d.id, {'deleted_at': 10, 'task_state': 0});
    List<int> ids(List<ClipboardModel> l) => [for (final x in l) x.id];
    expect(ids(await db.getClips()), [c.id, b.id, a.id]);
    expect(ids(await db.getClips(view: ClipView.tasks)), [c.id, b.id, a.id]);
    await set(c.id, {'deleted_at': 20});
    expect(ids(await db.getClips(view: ClipView.tasks)), [b.id, a.id]);
    expect(ids(await db.getClips(view: ClipView.trash)), [c.id, d.id]);
    expect(
      (await db.getClips(view: ClipView.trash)).first.deletedAt,
      DateTime.fromMillisecondsSinceEpoch(20),
    );
  });

  test('getClips filters by groupId and tag', () async {
    await db.rawDb.insert('groups', {'name': 'G'});
    final a = await db.insertClip('https://a.io', DateTime(2026, 1, 1));
    await db.insertClip('plain', DateTime(2026, 1, 2));
    await db.rawDb.update(
      'clips',
      {'group_id': 1},
      where: 'id = ?',
      whereArgs: [a.id],
    );
    await db.rawDb.insert('clip_tags', {'clip_id': a.id, 'tag': 'work'});
    expect((await db.getClips(groupId: 1)).map((e) => e.id), [a.id]);
    expect((await db.getClips(tag: 'LINK')).map((e) => e.id), [a.id]);
    expect((await db.getClips(tag: 'Work')).single.tags, ['Link', 'work']);
    expect(await db.getClips(tag: 'Email'), isEmpty);
  });

  test('foreign keys on, WAL requested', () async {
    final fk = await db.rawDb.rawQuery('PRAGMA foreign_keys');
    expect(fk.first.values.first, 1);
    final jm = await db.rawDb.rawQuery('PRAGMA journal_mode');
    expect(jm.first.values.first, anyOf('memory', 'wal'));
  });

  test('upgrade from v2 keeps rows and backfills tags', () async {
    final dir = await Directory.systemTemp.createTemp('clipps_v2');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/c.db';
    final v2 = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE clips('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'content TEXT NOT NULL, '
            'created_at INTEGER NOT NULL, '
            'source_app TEXT, source_title TEXT, '
            'pinned INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE INDEX idx_clips_created_at ON clips(created_at)',
          );
        },
      ),
    );
    await v2.insert('clips', {'content': 'one', 'created_at': 1, 'pinned': 1});
    await v2.insert('clips', {
      'content': 'two',
      'created_at': 2,
      'source_app': 'App',
      'source_title': 'T',
    });
    await v2.insert('clips', {'content': 'https://a.b', 'created_at': 3});
    await v2.insert('clips', {'content': '1' * 5000000, 'created_at': 4});
    await v2.close();

    final up = await DbHelper.open(databaseFactoryFfi, path);
    addTearDown(up.close);
    final got = await up.getClips();
    expect(got.length, 4);
    expect(
      (await up.rawDb.rawQuery('PRAGMA journal_mode')).first.values.first,
      'wal',
    );
    expect(got.where((c) => c.content.length == 5000000), hasLength(1));
    got.removeWhere((c) => c.content.length == 5000000);
    expect(got.map((c) => c.content), ['one', 'https://a.b', 'two']);
    expect(got.first.pinned, isTrue);
    expect(got.last.sourceApp, 'App');
    expect(got.last.sourceTitle, 'T');
    expect(got.every((c) => c.deletedAt == null), isTrue);
    expect(got.every((c) => c.taskState == TaskState.none), isTrue);
    expect(got.every((c) => c.groupId == null), isTrue);
    expect(got[1].tags, ['Link']);
    expect(got[0].tags, isEmpty);
    expect(got[2].tags, isEmpty);
    final auto = await up.rawDb.query('clip_tags', where: "tag = 'Link'");
    expect(auto.single['auto'], 1);
  });

  test('insertClip stores a 5M-digit clip', () async {
    final big = '1' * 5000000;
    final c = await db.insertClip(big, DateTime(2026));
    expect((await db.getClips()).single.content.length, big.length);
    expect(c.id, greaterThan(0));
  });
}
