import 'dart:io';

import 'package:clipps/database/db_helper.dart';
import 'package:clipps/models/clip_source.dart';
import 'package:clipps/models/clip_view.dart';
import 'package:clipps/models/clipboard_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  group('v3 mutations', () {
    final t0 = DateTime(2026, 6, 1);
    const fifteen = Duration(days: 15);

    test('trashClips skips pinned and returns count', () async {
      final a = await db.insertClip('a', t0);
      final b = await db.insertClip('b', t0);
      await db.setPinned(b.id, true);
      expect(await db.trashClips([a.id, b.id], t0), 1);
      expect(await db.trashClips([], t0), 0);
      expect((await db.getClips()).map((c) => c.id), [b.id]);
      expect((await db.getClips(view: ClipView.trash)).single.id, a.id);
    });

    test('restoreClips brings clips back to all', () async {
      final a = await db.insertClip('a', t0);
      await db.trashClips([a.id], t0);
      expect(await db.restoreClips([a.id]), 1);
      expect((await db.getClips()).single.id, a.id);
    });

    test('purgeTrashedBefore boundary', () async {
      final a = await db.insertClip('a', t0);
      final b = await db.insertClip('b', t0);
      final live = await db.insertClip('live', t0);
      await db.trashClips([
        a.id,
      ], t0.subtract(fifteen - const Duration(hours: 1)));
      await db.trashClips([
        b.id,
      ], t0.subtract(fifteen + const Duration(milliseconds: 1)));
      expect(await db.purgeTrashedBefore(t0.subtract(fifteen)), 1);
      expect((await db.getClips(view: ClipView.trash)).single.id, a.id);
      expect((await db.getClips()).single.id, live.id);
    });

    test('purge cascades clip_tags', () async {
      final a = await db.insertClip('https://x.com', t0);
      await db.addTag(a.id, 'work');
      await db.trashClips([a.id], t0);
      await db.purgeTrashedBefore(t0.add(const Duration(days: 1)));
      expect(await db.rawDb.query('clip_tags'), isEmpty);
    });

    test('setTaskState round-trips', () async {
      final a = await db.insertClip('a', t0);
      for (final s in [TaskState.open, TaskState.done, TaskState.none]) {
        await db.setTaskState(a.id, s);
        expect((await db.getClips()).single.taskState, s);
      }
    });

    test('group names are unique ignoring case', () async {
      await db.createGroup('Work');
      await expectLater(
        db.createGroup('work'),
        throwsA(isA<DatabaseException>()),
      );
      await db.createGroup('alpha');
      expect((await db.listGroups()).map((g) => g.name), ['alpha', 'Work']);
    });

    test('renameGroup renames', () async {
      final g = await db.createGroup('Old');
      await db.renameGroup(g.id, 'New');
      expect((await db.listGroups()).single.name, 'New');
    });

    test('deleteGroup keeps clips', () async {
      final g = await db.createGroup('Work');
      final a = await db.insertClip('a', t0);
      await db.setClipGroup(a.id, g.id);
      expect((await db.getClips(groupId: g.id)).single.id, a.id);
      await db.deleteGroup(g.id);
      final got = (await db.getClips()).single;
      expect(got.groupId, isNull);
      expect(await db.listGroups(), isEmpty);
    });

    test('addTag/removeTag and tagsInUse ignores trashed clips', () async {
      final a = await db.insertClip('see https://x.com', t0);
      final b = await db.insertClip('b', t0);
      await db.addTag(a.id, 'zed');
      await db.addTag(a.id, 'Zed'); // duplicate ignoring case
      await db.addTag(b.id, 'alpha');
      expect(await db.tagsInUse(), ['Link', 'alpha', 'zed']);
      await db.trashClips([b.id], t0);
      expect(await db.tagsInUse(), ['Link', 'zed']);
      await db.removeTag(a.id, 'ZED');
      expect(await db.tagsInUse(), ['Link']);
      expect((await db.getClips()).single.tags, ['Link']);
    });

    test('addTag rejects the separator character', () async {
      final a = await db.insertClip('a', t0);
      expect(() => db.addTag(a.id, 'x\u001Fy'), throwsArgumentError);
    });

    test('backupTo writes a readable copy', () async {
      final dir = await Directory.systemTemp.createTemp('clipps_bak');
      final src = await DbHelper.open(databaseFactoryFfi, '${dir.path}/src.db');
      try {
        await src.insertClip('a', t0);
        await src.insertClip('b', t0);
        final dest = '${dir.path}/copy.db';
        await src.backupTo(dest);
        final copy = await DbHelper.open(databaseFactoryFfi, dest);
        expect((await copy.getClips()).length, 2);
        await copy.close();
      } finally {
        await src.close();
        await dir.delete(recursive: true);
      }
    });
  });

  group('notes and settings', () {
    final t0 = DateTime(2026, 1, 1, 10);
    final t1 = DateTime(2026, 1, 1, 11);
    final t2 = DateTime(2026, 1, 1, 12);

    test('addNote and notesForClip newest first', () async {
      final c = await db.insertClip('x', t0);
      final a = await db.addNote(c.id, 'first', t0);
      final b = await db.addNote(c.id, 'second', t1);
      final d = await db.addNote(c.id, 'third', t1);
      expect(a.body, 'first');
      expect(a.createdAt, t0);
      expect(a.edited, isFalse);
      final got = await db.notesForClip(c.id);
      expect(got.map((n) => n.id), [d.id, b.id, a.id]);
    });

    test('addNote returns a note equal to its read-back', () async {
      final c = await db.insertClip('x', t0);
      final n = await db.addNote(
        c.id,
        'a',
        DateTime(2026, 1, 1, 10, 0, 0, 5, 7),
      );
      expect((await db.notesForClip(c.id)).single, n);
    });

    test('updateNote changes body and updated_at', () async {
      final c = await db.insertClip('x', t0);
      final n = await db.addNote(c.id, 'old', t0);
      expect(await db.updateNote(n.id, 'new', t1), isTrue);
      final got = (await db.notesForClip(c.id)).single;
      expect(got.body, 'new');
      expect(got.createdAt, t0);
      expect(got.updatedAt, t1);
      expect(got.edited, isTrue);
    });

    test('updateNote with same text keeps updated_at', () async {
      final c = await db.insertClip('x', t0);
      final n = await db.addNote(c.id, 'same', t0);
      expect(await db.updateNote(n.id, 'same', t2), isTrue);
      expect((await db.notesForClip(c.id)).single.updatedAt, t0);
    });

    test('updateNote on a missing id returns false', () async {
      expect(await db.updateNote(999, 'x', t0), isFalse);
    });

    test('deleteNote removes one note and returns 1', () async {
      final c = await db.insertClip('x', t0);
      final a = await db.addNote(c.id, 'a', t0);
      await db.addNote(c.id, 'b', t1);
      expect(await db.deleteNote(a.id), 1);
      expect(await db.deleteNote(a.id), 0);
      expect((await db.notesForClip(c.id)).single.body, 'b');
    });

    test(
      'notesView excludes trashed clips and shows the clip fields',
      () async {
        final live = await db.insertClip('live clip', t0);
        final gone = await db.insertClip('gone clip', t0);
        await db.addNote(live.id, 'older', t0);
        await db.addNote(live.id, 'newer', t1);
        await db.addNote(gone.id, 'hidden', t2);
        await db.trashClips([gone.id], t2);
        final view = await db.notesView();
        expect(view.map((e) => e.note.body), ['newer', 'older']);
        expect(view.first.clip.id, live.id);
        expect(view.first.clip.content, 'live clip');
      },
    );

    test('getClips carries note_count', () async {
      final a = await db.insertClip('a', t0);
      final b = await db.insertClip('b', t1);
      await db.addNote(a.id, 'n1', t0);
      await db.addNote(a.id, 'n2', t0);
      final got = {for (final c in await db.getClips()) c.id: c.noteCount};
      expect(got, {a.id: 2, b.id: 0});
    });

    test('purge removes notes of purged clips', () async {
      final c = await db.insertClip('x', t0);
      await db.addNote(c.id, 'n', t0);
      await db.trashClips([c.id], t0);
      expect(await db.purgeTrashedBefore(t2), 1);
      expect(await db.rawDb.query('notes'), isEmpty);
    });

    test('settings: null when absent, round-trip, overwrite', () async {
      expect(await db.getSetting('theme'), isNull);
      await db.setSetting('theme', 'dark');
      expect(await db.getSetting('theme'), 'dark');
      await db.setSetting('theme', 'light');
      expect(await db.getSetting('theme'), 'light');
    });
  });

  group('file-backed upgrade safety', () {
    late Directory dir;
    late String path;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('clipps_db_');
      path = p.join(dir.path, 'clipps.db');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> makeV2() async {
      final raw = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, _) => d.execute(
            'CREATE TABLE clips(id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'content TEXT NOT NULL, created_at INTEGER NOT NULL, '
            'source_app TEXT, source_title TEXT, '
            'pinned INTEGER NOT NULL DEFAULT 0)',
          ),
        ),
      );
      await raw.insert('clips', {'content': 'v2 clip', 'created_at': 1});
      await raw.close();
    }

    test('v3 -> v2 app -> v3 again keeps everything', () async {
      var h = await DbHelper.open(databaseFactoryFfi, path);
      final a = await h.insertClip('keep me a@b.co', DateTime(2026));
      await h.insertClip('other', DateTime(2026, 1, 2));
      await h.setPinned(a.id, true);
      await h.addTag(a.id, 'Work');
      final g = await h.createGroup('G');
      await h.setClipGroup(a.id, g.id);
      await h.close();

      final v2 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onDowngrade: (db, o, n) async {},
        ),
      );
      expect(await v2.getVersion(), 2);
      await v2.close();

      h = await DbHelper.open(databaseFactoryFfi, path);
      final clips = await h.getClips();
      expect(clips.length, 2);
      final got = clips.firstWhere((c) => c.id == a.id);
      expect(got.pinned, isTrue);
      expect(got.tags, containsAll(['Email', 'Work']));
      expect((await h.listGroups()).single.name, 'G');
      final row = await h.rawDb.query(
        'clips',
        where: 'id=?',
        whereArgs: [a.id],
      );
      expect(row.single['group_id'], g.id);
      await h.close();
    });

    test('backupBeforeUpgrade copies a v2 file once, skips v4', () async {
      await makeV2();
      final dest = p.join(dir.path, 'backups', 'clipps-pre-v4.db');
      await DbHelper.backupBeforeUpgrade(databaseFactoryFfi, path);
      expect(File(dest).existsSync(), isTrue);
      File(dest).writeAsStringSync('marker');
      await DbHelper.backupBeforeUpgrade(databaseFactoryFfi, path);
      expect(File(dest).readAsStringSync(), 'marker');

      // The upgraded file is v4 now: no new safety copy.
      File(dest).deleteSync();
      final h = await DbHelper.open(databaseFactoryFfi, path);
      await h.close();
      await DbHelper.backupBeforeUpgrade(databaseFactoryFfi, path);
      expect(File(dest).existsSync(), isFalse);
    });

    test('upgrade v3 keeps every row and writes the pre-v4 copy', () async {
      var h = await DbHelper.open(databaseFactoryFfi, path);
      final a = await h.insertClip('mail me a@b.co', DateTime(2026));
      await h.insertClip('two', DateTime(2026, 1, 2));
      await h.setPinned(a.id, true);
      await h.addTag(a.id, 'Work');
      final g = await h.createGroup('G');
      await h.setClipGroup(a.id, g.id);
      await h.close();

      final raw = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(),
      );
      await raw.execute('DROP TABLE notes');
      await raw.execute('DROP TABLE settings');
      await raw.execute('PRAGMA user_version = 3');
      await raw.close();

      await DbHelper.backupBeforeUpgrade(databaseFactoryFfi, path);
      final copy = p.join(dir.path, 'backups', 'clipps-pre-v4.db');
      expect(File(copy).existsSync(), isTrue);
      final c = await databaseFactoryFfi.openDatabase(
        copy,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await c.getVersion(), 3);
      expect(await c.query('clips'), hasLength(2));
      await c.close();

      h = await DbHelper.open(databaseFactoryFfi, path);
      final clips = await h.getClips();
      expect(clips.length, 2);
      final got = clips.firstWhere((x) => x.id == a.id);
      expect(got.pinned, isTrue);
      expect(got.groupId, g.id);
      expect(got.tags, containsAll(['Email', 'Work']));
      expect(got.noteCount, 0);
      expect((await h.listGroups()).single.name, 'G');
      expect(await h.rawDb.query('notes'), isEmpty);
      expect(await h.getSetting('x'), isNull);
      final v = await h.rawDb.rawQuery('PRAGMA user_version');
      expect(v.single.values.single, 4);
      await h.close();
    });

    test('deleteNote checkpoints on a file DB', () async {
      final h = await DbHelper.open(databaseFactoryFfi, path);
      final c = await h.insertClip('x', DateTime(2026));
      final n = await h.addNote(c.id, 'secret', DateTime(2026));
      expect(await h.deleteNote(n.id), 1);
      expect(await h.notesForClip(c.id), isEmpty);
      await h.close();
    });

    test('purge + checkpoint runs on a file DB', () async {
      final h = await DbHelper.open(databaseFactoryFfi, path);
      final c = await h.insertClip('gone', DateTime(2026));
      await h.trashClips([c.id], DateTime(2026));
      expect(await h.purgeTrashedBefore(DateTime(2027)), 1);
      await h.checkpoint();
      expect(await h.getClips(view: ClipView.trash), isEmpty);
      await h.close();
    });
  });

  test('duplicateIds finds repeats outside Trash only', () async {
    final t = DateTime(2026, 1, 1, 10);
    final a = await db.insertClip('same', t);
    await db.insertClip('other', t.add(const Duration(minutes: 1)));
    final c = await db.insertClip('same', t.add(const Duration(minutes: 2)));
    expect(await db.duplicateIds(), {a.id, c.id});
    await db.trashClips([c.id], t.add(const Duration(minutes: 3)));
    expect(await db.duplicateIds(), isEmpty);
  });
}
