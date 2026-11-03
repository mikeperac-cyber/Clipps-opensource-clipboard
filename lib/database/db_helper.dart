import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/clipboard_model.dart';

class DbHelper {
  final Database _db;
  DbHelper._(this._db);

  static Future<DbHelper> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
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
    return DbHelper._(db);
  }

  Future<ClipboardModel> insertClip(String content, DateTime createdAt) async {
    final ms = createdAt.millisecondsSinceEpoch;
    final id = await _db.insert('clips', {
      'content': content,
      'created_at': ms,
    });
    return ClipboardModel(id: id, content: content, createdAt: createdAt);
  }

  Future<ClipboardModel?> latestClip() async {
    final rows = await _db.query(
      'clips',
      orderBy: 'created_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : ClipboardModel.fromMap(rows.first);
  }

  Future<List<ClipboardModel>> getClips({
    String text = '',
    DateTime? from,
    DateTime? before,
  }) async {
    final where = <String>[];
    final args = <Object>[];
    if (text.isNotEmpty) {
      where.add(r"content LIKE ? ESCAPE '\'");
      final escaped = text.replaceAllMapped(
        RegExp(r'[\\%_]'),
        (m) => r'\' + m[0]!,
      );
      args.add('%$escaped%');
    }
    if (from != null) {
      where.add('created_at >= ?');
      args.add(from.millisecondsSinceEpoch);
    }
    if (before != null) {
      where.add('created_at < ?');
      args.add(before.millisecondsSinceEpoch);
    }
    final rows = await _db.query(
      'clips',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(ClipboardModel.fromMap).toList();
  }

  Future<int> deleteClips(Iterable<int> ids) async {
    if (ids.isEmpty) return 0;
    final marks = List.filled(ids.length, '?').join(',');
    return _db.delete(
      'clips',
      where: 'id IN ($marks)',
      whereArgs: ids.toList(),
    );
  }

  Future<void> close() => _db.close();
}
