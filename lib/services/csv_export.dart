import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/db_helper.dart';
import '../models/clipboard_model.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

String _field(String s) {
  // A leading ' stops spreadsheets from running the text as a formula.
  final safe = '=+-@\t\r'.contains(s.isEmpty ? ' ' : s[0]) ? "'$s" : s;
  return '"${safe.replaceAll('"', '""')}"';
}

String clipsToCsv(List<ClipboardModel> clips, Map<int, String> groupNames) {
  final b = StringBuffer(
    '\uFEFFCreated,Source app,Window title,Pinned,Group,Tags,Content\r\n',
  );
  for (final c in clips) {
    b.write(
      [
        _stamp(c.createdAt),
        c.sourceApp ?? '',
        c.sourceTitle ?? '',
        c.pinned ? 'yes' : '',
        groupNames[c.groupId] ?? '',
        c.tags.join('; '),
        c.content,
      ].map(_field).join(','),
    );
    b.write('\r\n');
  }
  return b.toString();
}

Future<String> exportClipsCsv(
  DbHelper db,
  Map<int, String> groupNames,
  Directory dir,
  DateTime now,
) async {
  final d = _stamp(now).replaceAll(' ', '-').replaceAll(':', '');
  final path = p.join(dir.path, 'Clipps-export-$d.csv');
  await File(path).writeAsString(clipsToCsv(await db.getClips(), groupNames));
  return path;
}
