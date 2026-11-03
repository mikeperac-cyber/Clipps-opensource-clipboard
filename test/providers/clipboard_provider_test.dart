import 'package:clipps/database/db_helper.dart';
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

  test('deleteSelected removes selected rows and clears selection', () async {
    await p.addClip('a');
    await p.addClip('b');
    await p.addClip('c');
    p.toggleSelected(p.clips[0].id);
    p.toggleSelected(p.clips[1].id);
    await p.deleteSelected();
    expect(p.clips.map((c) => c.content), ['a']);
    expect(p.selectedIds, isEmpty);
  });

  test('deleteClip removes one row and drops it from selection', () async {
    await p.addClip('a');
    await p.addClip('b');
    final id = p.clips.first.id;
    p.toggleSelected(id);
    await p.deleteClip(id);
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
    await p.deleteSelected();
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
}
