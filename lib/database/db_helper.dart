import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/clip_source.dart';
import '../models/clipboard_model.dart';

class DbHelper {
  final Database _db;
  DbHelper._(this._db);

  @visibleForTesting
  Database get rawDb => _db;

  static Future<DbHelper> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        // Deleted clip text must not linger in free pages on disk.
        onConfigure: (db) => db.execute('PRAGMA secure_delete = ON'),
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE clips('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'content TEXT NOT NULL, '
            'created_at INTEGER NOT NULL, '
            'source_app TEXT, '
            'source_title TEXT, '
            'pinned INTEGER NOT NULL DEFAULT 0)',
          );
          await db.execute(
            'CREATE INDEX idx_clips_created_at ON clips(created_at)',
          );
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE clips ADD COLUMN source_app TEXT');
            await db.execute('ALTER TABLE clips ADD COLUMN source_title TEXT');
            await db.execute(
              'ALTER TABLE clips ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
            );
          }
        },
      ),
    );
    return DbHelper._(db);
  }

  Future<ClipboardModel> insertClip(
    String content,
    DateTime createdAt, {
    ClipSource source = const ClipSource(),
  }) async {
    final app = source.app == '' ? null : source.app;
    final title = source.title == '' ? null : source.title;
    final id = await _db.insert('clips', {
      'content': content,
      'created_at': createdAt.millisecondsSinceEpoch,
      'source_app': app,
      'source_title': title,
    });
    return ClipboardModel(
      id: id,
      content: content,
      createdAt: createdAt,
      sourceApp: app,
      sourceTitle: title,
    );
  }

  Future<void> setPinned(int id, bool pinned) => _db.update(
    'clips',
    {'pinned': pinned ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

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
      orderBy: 'pinned DESC, created_at DESC, id DESC',
    );
    return rows.map(ClipboardModel.fromMap).toList();
  }

  Future<int> deleteClips(Iterable<int> ids) async {
    if (ids.isEmpty) return 0;
    final marks = List.filled(ids.length, '?').join(',');
    return _db.delete(
      'clips',
      where: 'id IN ($marks) AND pinned = 0',
      whereArgs: ids.toList(),
    );
  }

  Future<void> close() => _db.close();
}
