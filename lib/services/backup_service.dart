import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../database/db_helper.dart';

/// Keeps one `clipps-YYYY-MM-DD.db` copy per day, newest [keep] retained.
class BackupService {
  BackupService(this._db, this._dir, {this.clock = DateTime.now});

  static const keep = 7;
  static final _name = RegExp(r'^clipps-\d{4}-\d{2}-\d{2}\.db$');

  final DbHelper _db;
  final String _dir;
  final DateTime Function() clock;
  Timer? _timer;

  /// Returns the new backup path, or null if today's exists or it failed.
  Future<String?> backupIfDue() async {
    try {
      final d = clock();
      String two(int n) => n.toString().padLeft(2, '0');
      final target = p.join(
        _dir,
        'clipps-${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}.db',
      );
      if (File(target).existsSync()) return null;
      await Directory(_dir).create(recursive: true);
      // Write to a temp name so a crash never leaves a partial clipps-*.db.
      final tmp = File('$target.tmp');
      if (tmp.existsSync()) tmp.deleteSync();
      await _db.backupTo(tmp.path);
      tmp.renameSync(target);
      _prune();
      return target;
    } catch (e, s) {
      debugPrint('Clipps backup failed: $e\n$s');
      return null;
    }
  }

  void _prune() {
    final files = [
      for (final f in Directory(_dir).listSync())
        if (f is File && _name.hasMatch(p.basename(f.path))) f,
    ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final f in files.skip(keep)) {
      f.deleteSync();
    }
  }

  void start() {
    _timer?.cancel();
    unawaited(backupIfDue());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => backupIfDue());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
