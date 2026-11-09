import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/clip_group.dart';
import '../models/clip_source.dart';
import '../models/clip_view.dart';
import '../models/clipboard_model.dart';
import '../models/note.dart';
import '../services/auto_tagger.dart';

/// Current schema version. Each migration bumps it, and the pre-upgrade backup
/// follows it, so every future upgrade is copied before it runs.
const kSchemaVersion = 4;

class DbHelper {
  final Database _db;
  DbHelper._(this._db);

  @visibleForTesting
  Database get rawDb => _db;

  static Future<DbHelper> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: kSchemaVersion,
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
          await _createNotesAndSettings(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          // Every step is safe to re-run: the v2 app resets user_version to 2
          // when it opens a v3 file, so this can run on already-upgraded data.
          if (oldVersion < 2) {
            await _addColumn(db, 'source_app', 'TEXT');
            await _addColumn(db, 'source_title', 'TEXT');
            await _addColumn(db, 'pinned', 'INTEGER NOT NULL DEFAULT 0');
          }
          if (oldVersion < 3) {
            await _createGroups(db);
            await _addColumn(db, 'deleted_at', 'INTEGER');
            await _addColumn(db, 'task_state', 'INTEGER');
            await _addColumn(
              db,
              'group_id',
              'INTEGER REFERENCES groups(id) ON DELETE SET NULL',
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
                }, conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            }
            await batch.commit(noResult: true);
          }
          if (oldVersion < 4) await _createNotesAndSettings(db);
        },
      ),
    );
    return DbHelper._(db);
  }

  static Future<void> _addColumn(Database db, String name, String ddl) async {
    final cols = await db.rawQuery('PRAGMA table_info(clips)');
    if (cols.any((c) => c['name'] == name)) return;
    await db.execute('ALTER TABLE clips ADD COLUMN $name $ddl');
  }

  /// Copies a database older than [kSchemaVersion] (and its WAL files) to
  /// backups/clipps-pre-vN.db once, before the migration runs.
  /// Never throws: a failed copy must not block startup.
  static Future<void> backupBeforeUpgrade(
    DatabaseFactory factory,
    String path,
  ) async {
    try {
      final dir = Directory(p.join(p.dirname(path), 'backups'));
      final dest = p.join(dir.path, 'clipps-pre-v$kSchemaVersion.db');
      if (!File(path).existsSync() || File(dest).existsSync()) return;
      final probe = await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version = await probe.getVersion();
      await probe.close();
      if (version >= kSchemaVersion) return;
      await dir.create(recursive: true);
      // Sidecars first, main file last: its existence marks the copy as done.
      for (final suffix in ['-wal', '-shm', '']) {
        final src = File('$path$suffix');
        if (src.existsSync()) await src.copy('$dest$suffix');
      }
    } catch (e, s) {
      debugPrint('Clipps pre-upgrade backup failed: $e\n$s');
    }
  }

  static Future<void> _createGroups(Database db) => db.execute(
    'CREATE TABLE IF NOT EXISTS groups('
    'id INTEGER PRIMARY KEY AUTOINCREMENT, '
    'name TEXT NOT NULL UNIQUE COLLATE NOCASE)',
  );

  static Future<void> _createNotesAndSettings(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS notes('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE, '
      'body TEXT NOT NULL, '
      'created_at INTEGER NOT NULL, '
      'updated_at INTEGER NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notes_clip ON notes(clip_id)',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS settings('
      'key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  static Future<void> _createTagTable(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS clip_tags('
      'clip_id INTEGER NOT NULL REFERENCES clips(id) ON DELETE CASCADE, '
      'tag TEXT NOT NULL COLLATE NOCASE, '
      'auto INTEGER NOT NULL DEFAULT 0, '
      'PRIMARY KEY (clip_id, tag))',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_clip_tags_tag ON clip_tags(tag)',
    );
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
      'WHERE clip_id = clips.id) AS tags, '
      '(SELECT COUNT(*) FROM notes WHERE notes.clip_id = clips.id) '
      'AS note_count FROM clips';

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
      ClipView.notes => 'id DESC', // unused: the notes view lists notes
    };
    final rows = await _db.rawQuery(
      '$_select WHERE ${where.join(' AND ')} ORDER BY $order',
      args,
    );
    return rows.map(ClipboardModel.fromMap).toList();
  }

  static String _marks(Iterable<Object?> xs) =>
      List.filled(xs.length, '?').join(',');

  /// Moves unpinned live clips to the trash. Returns how many moved.
  Future<int> trashClips(Iterable<int> ids, DateTime now) async {
    if (ids.isEmpty) return 0;
    return _db.rawUpdate(
      'UPDATE clips SET deleted_at = ? WHERE id IN (${_marks(ids)}) '
      'AND pinned = 0 AND deleted_at IS NULL',
      [now.millisecondsSinceEpoch, ...ids],
    );
  }

  Future<int> restoreClips(Iterable<int> ids) async {
    if (ids.isEmpty) return 0;
    return _db.rawUpdate(
      'UPDATE clips SET deleted_at = NULL WHERE id IN (${_marks(ids)}) '
      'AND deleted_at IS NOT NULL',
      ids.toList(),
    );
  }

  /// The app's ONLY permanent delete: trashed rows strictly older than [cutoff].
  Future<int> purgeTrashedBefore(DateTime cutoff) async {
    final n = await _db.delete(
      'clips',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff.millisecondsSinceEpoch],
    );
    // Purged text must not linger in the -wal file.
    if (n > 0) await checkpoint();
    return n;
  }

  Future<void> checkpoint() => _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

  Future<void> setTaskState(int id, TaskState state) => _db.update(
    'clips',
    {
      'task_state': switch (state) {
        TaskState.none => null,
        TaskState.open => 0,
        TaskState.done => 1,
      },
    },
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<List<ClipGroup>> listGroups() async {
    final rows = await _db.query('groups', orderBy: 'name COLLATE NOCASE');
    return [
      for (final r in rows)
        ClipGroup(id: r['id'] as int, name: r['name'] as String),
    ];
  }

  /// Throws [DatabaseException] if the name exists (ignoring case).
  Future<ClipGroup> createGroup(String name) async =>
      ClipGroup(id: await _db.insert('groups', {'name': name}), name: name);

  Future<void> renameGroup(int id, String name) =>
      _db.update('groups', {'name': name}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteGroup(int id) =>
      _db.delete('groups', where: 'id = ?', whereArgs: [id]);

  Future<void> setClipGroup(int clipId, int? groupId) => _db.update(
    'clips',
    {'group_id': groupId},
    where: 'id = ?',
    whereArgs: [clipId],
  );

  Future<void> addTag(int clipId, String tag) async {
    // U+001F is the group_concat separator on read.
    if (tag.contains('')) throw ArgumentError.value(tag, 'tag');
    await _db.insert('clip_tags', {
      'clip_id': clipId,
      'tag': tag,
      'auto': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> removeTag(int clipId, String tag) => _db.delete(
    'clip_tags',
    where: 'clip_id = ? AND tag = ?',
    whereArgs: [clipId, tag],
  );

  /// Tags on live clips: [kAutoTags] order first, then the rest A-Z.
  Future<List<String>> tagsInUse() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT tag FROM clip_tags JOIN clips ON clips.id = clip_id '
      'WHERE deleted_at IS NULL',
    );
    final tags = [for (final r in rows) r['tag'] as String];
    int rank(String t) {
      final i = kAutoTags.indexOf(t);
      return i < 0 ? kAutoTags.length : i;
    }

    return tags..sort((a, b) {
      final c = rank(a).compareTo(rank(b));
      return c != 0 ? c : a.toLowerCase().compareTo(b.toLowerCase());
    });
  }

  Future<String?> getSetting(String key) async {
    final rows = await _db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) => _db.insert('settings', {
    'key': key,
    'value': value,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Stores [body] exactly as given; the length limit is the provider's job.
  Future<Note> addNote(int clipId, String body, DateTime now) async {
    final ms = now.millisecondsSinceEpoch;
    final id = await _db.insert('notes', {
      'clip_id': clipId,
      'body': body,
      'created_at': ms,
      'updated_at': ms,
    });
    return Note(
      id: id,
      clipId: clipId,
      body: body,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  /// True when the note exists; identical text leaves updated_at alone.
  Future<bool> updateNote(int id, String body, DateTime now) async {
    final rows = await _db.query(
      'notes',
      columns: ['body'],
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return false;
    if (rows.first['body'] == body) return true;
    return await _db.update(
          'notes',
          {'body': body, 'updated_at': now.millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [id],
        ) >
        0;
  }

  Future<int> deleteNote(int id) =>
      _db.delete('notes', where: 'id = ?', whereArgs: [id]);

  Future<List<Note>> notesForClip(int clipId) async {
    final rows = await _db.query(
      'notes',
      where: 'clip_id = ?',
      whereArgs: [clipId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  /// Notes on live clips, most recently touched first.
  Future<List<NoteEntry>> notesView() async {
    final rows = await _db.rawQuery(
      'SELECT notes.id AS n_id, notes.clip_id AS n_clip_id, '
      'notes.body AS n_body, notes.created_at AS n_created_at, '
      'notes.updated_at AS n_updated_at, clips.*, '
      '(SELECT group_concat(tag, char(31)) FROM clip_tags '
      'WHERE clip_id = clips.id) AS tags, '
      '(SELECT COUNT(*) FROM notes n2 WHERE n2.clip_id = clips.id) '
      'AS note_count '
      'FROM notes JOIN clips ON clips.id = notes.clip_id '
      'WHERE clips.deleted_at IS NULL '
      'ORDER BY notes.updated_at DESC, notes.id DESC',
    );
    return [
      for (final r in rows)
        NoteEntry(
          note: Note.fromMap({
            'id': r['n_id'],
            'clip_id': r['n_clip_id'],
            'body': r['n_body'],
            'created_at': r['n_created_at'],
            'updated_at': r['n_updated_at'],
          }),
          clip: ClipboardModel.fromMap(r),
        ),
    ];
  }

  Future<void> backupTo(String path) => _db.rawQuery('VACUUM INTO ?', [path]);

  Future<void> close() => _db.close();
}
