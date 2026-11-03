import 'package:clipps/database/db_helper.dart';
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
}
