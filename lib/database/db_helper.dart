import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/clip_source.dart';
import '../models/clip_view.dart';
import '../models/clipboard_model.dart';
import '../services/auto_tagger.dart';

class DbHelper {
  final Database _db;
  DbHelper._(this._db);

  @visibleForTesting
  Database get rawDb => _db;

  static Future<DbHelper> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onConfigure: (db) async {
          // Deleted clip text must not linger in free pages on disk.
          await db.execute('PRAGMA secure_delete = ON');
          await db.execute('PRAGMA foreign_keys = ON');
          // journal_mode returns a row, so execute() would throw.
          await db.rawQuery('PRAGMA journal_mode = WAL');
        },
        onCreate: (db, _) async {
          await _createGroups(db);
          await db.execute(
            'CREATE TABLE clips('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'content TEXT NOT NULL, '
            'created_at INTEGER NOT NULL, '
            'source_app TEXT, '
            'source_title TEXT, '
            'pinned INTEGER NOT NULL DEFAULT 0, '
            'deleted_at INTEGER, '
            'task_state INTEGER, '
            'group_id INTEGER REFERENCES groups(id) ON DELETE SET NULL)',
          );
          await db.execute(
            'CREATE INDEX idx_clips_created_at ON clips(created_at)',
          );
          await _createTagTable(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE clips ADD COLUMN source_app TEXT');
            await db.execute('ALTER TABLE clips ADD COLUMN source_title TEXT');
            await db.execute(
              'ALTER TABLE clips ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
            );
          }
          if (oldVersion < 3) {
            await _createGroups(db);
            await db.execute('ALTER TABLE clips ADD COLUMN deleted_at INTEGER');
            await db.execute('ALTER TABLE clips ADD COLUMN task_state INTEGER');
            await db.execute(
              'ALTER TABLE clips ADD COLUMN group_id INTEGER '
              'REFERENCES groups(id) ON DELETE SET NULL',
            );
            await _createTagTable(db);
            final rows = await db.query('clips', columns: ['id', 'content']);
            final batch = db.batch();
            for (final r in rows) {
              for (final t in detectTags(r['content'] as String)) {
                batch.insert('clip_tags', {
                  'clip_id': r['id'],
                  'tag': t,
                  'auto': 1,
                });
              }
            }
            await batch.commit(noResult: true);
          }
        },
      ),
    );
    return DbHelper._(db);
  }

  static Future<void> _createGroups(Database db) => db.execute(
    'CREATE TABLE groups('
    'id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'name TEXT NOT NULL UNIQUE COLLATE NOCASE)',
  );

  static Future<void> _createTagTable(Database db) async {
    await db.execute(
      'CREATE TABLE clip_tags('
      'clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE, '
      'tag TEXT NOT NULL COLLATE NOCASE, '
      'auto INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (clip_id, tag))',
    );
    await db.execute('CREATE INDEX idx_clip_tags_tag ON clip_tags(tag)');
  }

  Future<ClipboardModel> insertClip(
    String content,
    DateTime createdAt, {
    ClipSource source = const ClipSource(),
  }) async {
    final app = source.app == '' ? null : source.app;
    final title = source.title == '' ? null : source.title;
    final tags = detectTags(content);
    final id = await _db.transaction((txn) async {
      final id = await txn.insert('clips', {
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
        'source_app': app,
        'source_title': title,
      });
      for (final t in tags) {
        await txn.insert('clip_tags', {'clip_id': id, 'tag': t, 'auto': 1});
      }
      return id;
    });
    return ClipboardModel(
      id: id,
      content: content,
      createdAt: createdAt,
      sourceApp: app,
      sourceTitle: title,
      tags: tags,
    );
  }

  Future<void> setPinned(int id, bool pinned) => _db.update(
    'clips',
    {'pinned': pinned ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  static const _select =
      'SELECT clips.*, (SELECT group_concat(tag, char(31)) FROM clip_tags '
      'WHERE clip_id = clips.id) AS tags FROM clips';

  Future<ClipboardModel?> latestClip() async {
    final rows = await _db.rawQuery(
      '$_select WHERE deleted_at IS NULL '
      'ORDER BY created_at DESC, id DESC LIMIT 1',
    );
    return rows.isEmpty ? null : ClipboardModel.fromMap(rows.first);
  }

  Future<List<ClipboardModel>> getClips({
    String text = '',
    DateTime? from,
    DateTime? before,
    ClipView view = ClipView.all,
    int? groupId,
    String? tag,
  }) async {
    final where = <String>[
      view == ClipView.trash ? 'deleted_at IS NOT NULL' : 'deleted_at IS NULL',
      if (view == ClipView.tasks) 'task_state IS NOT NULL',
    ];
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
    if (groupId != null) {
      where.add('group_id = ?');
      args.add(groupId);
    }
    if (tag != null) {
      where.add(
        'EXISTS (SELECT 1 FROM clip_tags '
        'WHERE clip_id = clips.id AND tag = ?)',
      );
      args.add(tag);
    }
    final order = switch (view) {
      ClipView.all => 'pinned DESC, created_at DESC, id DESC',
      ClipView.tasks => 'task_state ASC, created_at DESC, id DESC',
      ClipView.trash => 'deleted_at DESC, id DESC',
    };
    final rows = await _db.rawQuery(
      '$_select WHERE ${where.join(' AND ')} ORDER BY $order',
      args,
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
