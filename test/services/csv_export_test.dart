import 'dart:io';

import 'package:clipps/database/db_helper.dart';
import 'package:clipps/models/clipboard_model.dart';
import 'package:clipps/services/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ClipboardModel clip({
  String content = 'x',
  bool pinned = false,
  int? groupId,
  List<String> tags = const [],
}) => ClipboardModel(
  id: 1,
  content: content,
  createdAt: DateTime(2026, 3, 4, 5, 6),
  sourceApp: 'app',
  pinned: pinned,
  groupId: groupId,
  tags: tags,
);

void main() {
  setUpAll(sqfliteFfiInit);

  test('csv quotes commas, quotes and newlines', () {
    final csv = clipsToCsv([clip(content: 'a, "b"\nc')], {});
    expect(
      csv,
      startsWith(
        '\uFEFFCreated,Source app,Window title,Pinned,Group,Tags,Content\r\n',
      ),
    );
    expect(csv, contains('"a, ""b""\nc"'));
  });

  test('csv neutralises formulas', () {
    expect(
      clipsToCsv([clip(content: '=HYPERLINK("x")')], {}),
      contains('"\'=HYPERLINK(""x"")"'),
    );
  });

  test('csv fills group name, tags and pinned', () {
    final csv = clipsToCsv(
      [
        clip(pinned: true, groupId: 1, tags: ['link', 'todo']),
      ],
      {1: 'Work'},
    );
    expect(
      csv,
      contains('"2026-03-04 05:06","app","","yes","Work","link; todo","x"\r\n'),
    );
  });

  test('export writes the file and skips Trash', () async {
    final tmp = await Directory.systemTemp.createTemp('clipps_csv_');
    final db = await DbHelper.open(
      databaseFactoryFfi,
      p.join(tmp.path, 'c.db'),
    );
    addTearDown(() async {
      await db.close();
      await tmp.delete(recursive: true);
    });
    final t = DateTime(2026, 1, 1);
    await db.insertClip('one', t);
    await db.insertClip('two\nlines', t);
    final gone = await db.insertClip('trashed', t);
    await db.trashClips([gone.id], t);

    final path = await exportClipsCsv(
      db,
      {},
      tmp,
      DateTime(2026, 11, 9, 14, 5),
    );
    expect(p.basename(path), 'Clipps-export-2026-11-09-1405.csv');
    final text = File(path).readAsStringSync();
    expect(text, contains('"one"'));
    expect(text, contains('"two\nlines"'));
    expect(text, isNot(contains('trashed')));
    expect(File(path).readAsBytesSync().take(3), [0xEF, 0xBB, 0xBF]);
  });
}
