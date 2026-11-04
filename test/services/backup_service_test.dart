import 'dart:io';

import 'package:clipps/database/db_helper.dart';
import 'package:clipps/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory tmp;
  late DbHelper db;
  late String backups;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clipps_backup_');
    db = await DbHelper.open(databaseFactoryFfi, p.join(tmp.path, 'clipps.db'));
    backups = p.join(tmp.path, 'backups');
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  List<String> names() =>
      [for (final f in Directory(backups).listSync()) p.basename(f.path)]
        ..sort();

  BackupService svc() =>
      BackupService(db, backups, clock: () => DateTime(2026, 11, 4, 9));

  test('creates today\'s backup once', () async {
    final s = svc();
    final path = await s.backupIfDue();
    expect(path, p.join(backups, 'clipps-2026-11-04.db'));
    expect(await s.backupIfDue(), isNull);
    expect(names(), ['clipps-2026-11-04.db']);
  });

  test('keeps the newest 7 backups', () async {
    Directory(backups).createSync(recursive: true);
    for (var d = 1; d <= 8; d++) {
      File(p.join(backups, 'clipps-2026-10-0$d.db')).writeAsStringSync('x');
    }
    await svc().backupIfDue();
    final n = names();
    expect(n.length, 7);
    expect(n.last, 'clipps-2026-11-04.db');
    expect(n, isNot(contains('clipps-2026-10-01.db')));
    expect(n, isNot(contains('clipps-2026-10-02.db')));
  });

  test('ignores unrelated files in the folder', () async {
    Directory(backups).createSync(recursive: true);
    for (var i = 0; i < 9; i++) {
      File(p.join(backups, 'notes$i.txt')).writeAsStringSync('x');
    }
    await svc().backupIfDue();
    expect(names().where((n) => n.startsWith('notes')).length, 9);
  });

  test('recovers from a stale partial temp file', () async {
    Directory(backups).createSync(recursive: true);
    File(p.join(backups, 'clipps-2026-11-04.db.tmp')).writeAsStringSync('x');
    expect(await svc().backupIfDue(), isNotNull);
    expect(names(), ['clipps-2026-11-04.db']);
  });

  test('failure returns null instead of throwing', () async {
    await db.close();
    expect(await svc().backupIfDue(), isNull);
    db = await DbHelper.open(databaseFactoryFfi, p.join(tmp.path, 'clipps.db'));
  });
}
