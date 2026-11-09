import 'package:clipps/database/db_helper.dart';
import 'package:clipps/models/clip_source.dart';
import 'package:clipps/models/clip_view.dart';
import 'package:clipps/models/clipboard_model.dart';
import 'package:clipps/providers/clipboard_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late DbHelper db;
  late ClipboardProvider p;
  late DateTime now;
  setUp(() async {
    now = DateTime(2026, 1, 1, 10);
    db = await DbHelper.open(databaseFactoryFfi, inMemoryDatabasePath);
    p = ClipboardProvider(db, clock: () => now);
  });
  tearDown(() => db.close());

  test('addClip saves with clock time and shows it first', () async {
    expect(await p.addClip('a'), isTrue);
    expect(p.clips.first.content, 'a');
    expect(p.clips.first.createdAt, now);
  });

  test('addClip stores content unchanged, including whitespace', () async {
    await p.addClip('  a\n');
    expect(p.clips.first.content, '  a\n');
  });

  test('addClip skips empty and whitespace-only text', () async {
    expect(await p.addClip(''), isFalse);
    expect(await p.addClip('  \n\t'), isFalse);
    expect(p.clips, isEmpty);
  });

  test('addClip skips text equal to the most recent clip', () async {
    expect(await p.addClip('a'), isTrue);
    expect(await p.addClip('a'), isFalse);
    expect((await db.getClips()).length, 1);
    await p.addClip('b');
    await p.addClip('a');
    expect((await db.getClips()).length, 3);
  });

  test('concurrent addClip of the same text stores one row', () async {
    final results = await Future.wait([p.addClip('x'), p.addClip('x')]);
    expect(results, [true, false]);
    expect((await db.getClips()).length, 1);
  });

  test('dedupe compares against the newest clip even when filtered', () async {
    await p.addClip('a');
    await p.setSearchText('zzz');
    expect(await p.addClip('a'), isFalse);
  });

  test('setSearchText filters clips', () async {
    await p.addClip('apple');
    await p.addClip('banana');
    await p.setSearchText('nan');
    expect(p.searchText, 'nan');
    expect(p.clips.map((c) => c.content), ['banana']);
  });

  Future<void> addAt(DateTime t) async {
    now = t;
    await p.addClip(t.toString());
  }

  test('setDateRange includes the whole end day', () async {
    await addAt(DateTime(2026, 1, 1));
    await addAt(DateTime(2026, 1, 2, 23, 59));
    await addAt(DateTime(2026, 1, 3));
    await p.setDateRange(
      DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 2)),
    );
    expect(p.clips.length, 2);
    expect(p.dateRange, isNotNull);
  });

  test('setDateRange(null) clears the date filter', () async {
    await addAt(DateTime(2026, 1, 1));
    await addAt(DateTime(2026, 1, 3));
    await p.setDateRange(
      DateTimeRange(start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 1)),
    );
    expect(p.clips.length, 1);
    await p.setDateRange(null);
    expect(p.dateRange, isNull);
    expect(p.clips.length, 2);
  });

  test('new clip failing the active filter is saved but not listed', () async {
    await p.setSearchText('keep');
    expect(await p.addClip('other'), isTrue);
    expect(p.clips, isEmpty);
    expect((await db.getClips()).length, 1);
  });

  test('toggleSelected adds then removes an id', () {
    p.toggleSelected(1);
    expect(p.selectedIds, {1});
    p.toggleSelected(1);
    expect(p.selectedIds, isEmpty);
  });

  test('trashSelected trashes selected rows and clears selection', () async {
    await p.addClip('a');
    await p.addClip('b');
    await p.addClip('c');
    p.toggleSelected(p.clips[0].id);
    p.toggleSelected(p.clips[1].id);
    await p.trashSelected();
    expect(p.clips.map((c) => c.content), ['a']);
    expect(p.selectedIds, isEmpty);
  });

  test('trashClip trashes one row and drops it from selection', () async {
    await p.addClip('a');
    await p.addClip('b');
    final id = p.clips.first.id;
    p.toggleSelected(id);
    await p.trashClip(id);
    expect(p.clips.map((c) => c.content), ['a']);
    expect(p.selectedIds, isEmpty);
  });

  test('mutations notify listeners', () async {
    var n = 0;
    p.addListener(() => n++);
    await p.addClip('a');
    expect(n, 1);
    await p.setSearchText('a');
    expect(n, 2);
    p.toggleSelected(p.clips.first.id);
    expect(n, 3);
    await p.trashSelected();
    expect(n, 4);
  });

  test('changing search text or date range clears the selection', () async {
    await p.addClip('a');
    p.toggleSelected(p.clips.first.id);
    await p.setSearchText('zzz');
    expect(p.selectedIds, isEmpty);
    await p.setSearchText('');
    p.toggleSelected(p.clips.first.id);
    await p.setDateRange(null);
    expect(p.selectedIds, isEmpty);
  });

  test('addClip stores the source', () async {
    await p.addClip(
      'a',
      source: const ClipSource(app: 'Code', title: 'T'),
    );
    expect(p.clips.first.sourceApp, 'Code');
    expect(p.clips.first.sourceTitle, 'T');
  });

  test('dedupe ignores pins', () async {
    await p.addClip('a');
    now = now.add(const Duration(minutes: 1));
    await p.addClip('b');
    await p.togglePin(p.clips.firstWhere((c) => c.content == 'a').id);
    expect(await p.addClip('b'), isFalse);
    expect(await p.addClip('a'), isTrue);
  });

  test('togglePin pins, unpins and removes from selection', () async {
    await p.addClip('a');
    final id = p.clips.first.id;
    p.toggleSelected(id);
    await p.togglePin(id);
    expect(p.clips.first.pinned, isTrue);
    expect(p.selectedIds, isEmpty);
    await p.togglePin(id);
    expect(p.clips.first.pinned, isFalse);
    await p.togglePin(9999); // unknown id: no-op
  });

  test('requestSearchFocus increments and notifies', () {
    var n = 0;
    p.addListener(() => n++);
    p.requestSearchFocus();
    expect(p.searchFocusRequests, 1);
    expect(n, 1);
  });

  test('markHotkeyUnavailable sets flag and notifies', () {
    var n = 0;
    p.addListener(() => n++);
    expect(p.hotkeyUnavailable, isFalse);
    p.markHotkeyUnavailable();
    expect(p.hotkeyUnavailable, isTrue);
    expect(n, 1);
  });

  group('v3 state', () {
    test('trashClip hides from all and shows in trash', () async {
      await p.addClip('a');
      await p.trashClip(p.clips.first.id);
      expect(p.clips, isEmpty);
      await p.setView(ClipView.trash);
      expect(p.clips.single.content, 'a');
      await p.restoreClip(p.clips.first.id);
      expect(p.clips, isEmpty);
      await p.setView(ClipView.all);
      expect(p.clips.single.content, 'a');
    });

    test('purgeExpiredTrash uses 15 days', () async {
      await p.addClip('keep');
      await p.addClip('gone');
      final keep = p.clips[1].id, gone = p.clips[0].id;
      await db.trashClips([
        keep,
      ], now.subtract(const Duration(days: 15) - const Duration(hours: 1)));
      await db.trashClips([
        gone,
      ], now.subtract(const Duration(days: 15, milliseconds: 1)));
      expect(await p.purgeExpiredTrash(), 1);
      await p.setView(ClipView.trash);
      expect(p.clips.map((c) => c.id), [keep]);
    });

    test('load purges expired trash', () async {
      await p.addClip('x');
      await db.trashClips([p.clips.first.id], now);
      now = now.add(kTrashRetention + const Duration(milliseconds: 1));
      await p.load();
      await p.setView(ClipView.trash);
      expect(p.clips, isEmpty);
    });

    test('dedupe re-adds text that is in trash', () async {
      await p.addClip('a');
      await p.trashClip(p.clips.first.id);
      expect(await p.addClip('a'), isTrue);
    });

    test('setView tasks lists open tasks first', () async {
      await p.addClip('a');
      await p.addClip('b');
      final a = p.clips[1].id, b = p.clips[0].id;
      await p.makeTask(b);
      await p.makeTask(a);
      await p.setTaskDone(b, true);
      await p.setView(ClipView.tasks);
      expect(p.clips.map((c) => c.id), [a, b]);
      expect(p.clips.last.taskState, TaskState.done);
      await p.removeTask(a);
      expect(p.clips.map((c) => c.id), [b]);
    });

    test('selectGroup filters and deleteGroup clears the selection', () async {
      await p.addClip('a');
      await p.addClip('b');
      expect(await p.createGroup('Work'), isTrue);
      final g = p.groups.single.id;
      await p.setClipGroup(p.clips.first.id, g);
      await p.selectGroup(g);
      expect(p.groupId, g);
      expect(p.clips.map((c) => c.content), ['b']);
      await p.deleteGroup(g);
      expect(p.groupId, isNull);
      expect(p.groups, isEmpty);
      expect(p.clips, hasLength(2));
      await p.selectGroup(1);
      await p.setView(ClipView.all);
      expect(p.groupId, isNull);
    });

    test('createGroup rejects duplicates and empty names', () async {
      expect(await p.createGroup('Work'), isTrue);
      expect(await p.createGroup(' work '), isFalse);
      expect(await p.createGroup(''), isFalse);
      expect(await p.createGroup('a\nb'), isFalse);
      expect(await p.createGroup('x' * 41), isFalse);
      expect(await p.createGroup('x' * 40), isTrue);
      expect(await p.createGroup('Home'), isTrue);
      final home = p.groups.firstWhere((g) => g.name == 'Home').id;
      expect(await p.renameGroup(home, 'WORK'), isFalse);
      expect(await p.renameGroup(home, ' Casa '), isTrue);
      expect(p.groups.any((g) => g.name == 'Casa'), isTrue);
    });

    test('addTag validates length and updates tagsInUse', () async {
      await p.addClip('a');
      final id = p.clips.first.id;
      expect(await p.addTag(id, ''), isFalse);
      expect(await p.addTag(id, '  '), isFalse);
      expect(await p.addTag(id, 'x' * 31), isFalse);
      expect(await p.addTag(id, 'a\u001Fb'), isFalse);
      expect(await p.addTag(id, ' todo '), isTrue);
      expect(p.tagsInUse, contains('todo'));
      expect(p.clips.first.tags, contains('todo'));
      await p.removeTag(id, 'todo');
      expect(p.tagsInUse, isNot(contains('todo')));
    });

    test('setTagFilter narrows clips', () async {
      await p.addClip('a');
      await p.addClip('b');
      await p.addTag(p.clips.first.id, 'one');
      await p.setTagFilter('one');
      expect(p.tagFilter, 'one');
      expect(p.clips.map((c) => c.content), ['b']);
      await p.setTagFilter(null);
      expect(p.clips, hasLength(2));
    });

    test('startRetentionTimer is cancelled by dispose', () async {
      p.startRetentionTimer();
      p.dispose();
      p = ClipboardProvider(db, clock: () => now);
    });
  });

  group('notes and theme', () {
    Future<int> clip() async {
      await p.addClip('c${p.clips.length}');
      return p.clips.first.id;
    }

    test('themeFromSetting defaults to system', () {
      for (final v in [null, '', 'blue']) {
        expect(themeFromSetting(v), ThemeMode.system);
      }
      expect(themeFromSetting('light'), ThemeMode.light);
      expect(themeFromSetting('dark'), ThemeMode.dark);
    });

    test('setThemeMode saves and notifies; new provider reads it', () async {
      var n = 0;
      p.addListener(() => n++);
      await p.setThemeMode(ThemeMode.dark);
      expect(n, 1);
      expect(p.themeMode, ThemeMode.dark);
      final q = ClipboardProvider(db, clock: () => now);
      await q.load();
      expect(q.themeMode, ThemeMode.dark);
      await p.setThemeMode(ThemeMode.system);
      expect(await db.getSetting('theme'), 'system');
    });

    test('addNote refuses blank and whitespace-only', () async {
      final id = await clip();
      expect(await p.addNote(id, ''), NoteResult.blank);
      expect(await p.addNote(id, ' \n\t'), NoteResult.blank);
      expect(await p.notesFor(id), isEmpty);
    });

    test('addNote refuses over 20,000 characters', () async {
      final id = await clip();
      expect(await p.addNote(id, 'a' * 20001), NoteResult.tooLong);
      expect(await p.addNote(id, 'a' * 20000), NoteResult.saved);
      expect((await p.notesFor(id)).length, 1);
    });

    test('addNote keeps newlines and emoji intact', () async {
      final id = await clip();
      const body = 'line 1\n\u{1F44D}\u{1F3FD} line 2 ';
      await p.addNote(id, body);
      expect((await p.notesFor(id)).single.body, body);
      expect(p.clips.first.noteCount, 1);
    });

    test('editNote changes text; same text does not change edited', () async {
      final id = await clip();
      await p.addNote(id, 'a');
      final n = (await p.notesFor(id)).single;
      now = now.add(const Duration(minutes: 1));
      expect(await p.editNote(n.id, 'a'), NoteResult.saved);
      expect((await p.notesFor(id)).single.edited, isFalse);
      expect(await p.editNote(n.id, 'b'), NoteResult.saved);
      final e = (await p.notesFor(id)).single;
      expect(e.body, 'b');
      expect(e.edited, isTrue);
      expect(await p.editNote(n.id, '  '), NoteResult.blank);
      expect(await p.editNote(n.id, 'a' * 20001), NoteResult.tooLong);
    });

    test('deleteNote removes it and notifies', () async {
      final id = await clip();
      await p.addNote(id, 'a');
      final n = (await p.notesFor(id)).single;
      var c = 0;
      p.addListener(() => c++);
      await p.deleteNote(n.id);
      expect(c, 1);
      expect(await p.notesFor(id), isEmpty);
      expect(p.clips.first.noteCount, 0);
    });

    test('notes list excludes trashed clips; view clears state', () async {
      final a = await clip();
      final b = await clip();
      await p.addNote(a, 'x');
      await p.addNote(b, 'y');
      await p.trashClip(b);
      await p.createGroup('g');
      await p.selectGroup(p.groups.first.id);
      p.toggleSelected(a);
      await p.setView(ClipView.notes);
      expect(p.selectedIds, isEmpty);
      expect(p.groupId, isNull);
      expect(p.clips, isEmpty);
      expect(p.notes.map((e) => e.note.body), ['x']);
      await p.setView(ClipView.all);
      expect(p.notes, isEmpty);
    });
  });
}
