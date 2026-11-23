import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Queue + history of everything shared. One table; status says where an item is.
class Db {
  Db._(this._db);
  final Database _db;

  static Future<Db> open() async {
    final dir = await getDatabasesPath();
    final newPath = p.join(dir, 'tandem.db');
    final oldPath = p.join(dir, 'phonesaves.db');
    if (!await databaseExists(newPath) && await databaseExists(oldPath)) {
      try {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) {
          await oldFile.rename(newPath);
        }
      } catch (_) {}
    }
    final db = await openDatabase(
      newPath,
      version: 2,
      onCreate: (d, _) => d.execute('''
        CREATE TABLE items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          name TEXT NOT NULL,
          path TEXT,
          url TEXT,
          size INTEGER,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          error TEXT,
          created_at INTEGER NOT NULL,
          claimed_at INTEGER,
          sent_at INTEGER,
          target_fingerprint TEXT,
          relative_path TEXT,
          temporary INTEGER NOT NULL DEFAULT 0,
          duplicate_action TEXT,
          resume_error TEXT
        )'''),
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await d.execute('ALTER TABLE items ADD COLUMN target_fingerprint TEXT');
          await d.execute('ALTER TABLE items ADD COLUMN relative_path TEXT');
          await d.execute('ALTER TABLE items ADD COLUMN temporary INTEGER NOT NULL DEFAULT 0');
          await d.execute('ALTER TABLE items ADD COLUMN duplicate_action TEXT');
          await d.execute('ALTER TABLE items ADD COLUMN resume_error TEXT');
        }
      },
    );
    return Db._(db);
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  Future<int> insert(QueueItem i) => _db.insert('items', i.toMap());

  Future<QueueItem?> get(int id) async {
    final r = await _db.query('items', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : QueueItem.fromMap(r.first);
  }

  Future<List<QueueItem>> byStatus(List<ItemStatus> statuses,
      {String order = 'created_at ASC', int? limit}) async {
    final r = await _db.query(
      'items',
      where: 'status IN (${statuses.map((_) => '?').join(',')})',
      whereArgs: statuses.map((s) => s.name).toList(),
      orderBy: order,
      limit: limit,
    );
    return r.map(QueueItem.fromMap).toList();
  }

  /// Atomically takes a queued item so two flushers (app + background) never send it twice.
  Future<bool> claim(int id) async {
    final n = await _db.rawUpdate(
      "UPDATE items SET status = 'sending', claimed_at = ?, resume_error = NULL WHERE id = ? AND status = 'queued'",
      [_now, id],
    );
    return n == 1;
  }

  /// Items left in 'sending' by a crashed run go back to the queue after 5 minutes.
  Future<void> resetStuck() => _db.rawUpdate(
        "UPDATE items SET status = 'queued' WHERE status = 'sending' AND (claimed_at IS NULL OR claimed_at < ?)",
        [_now - const Duration(minutes: 5).inMilliseconds],
      );

  Future<void> requeue(int id, String? error) => _db.rawUpdate(
        "UPDATE items SET status = 'queued', attempts = attempts + 1, resume_error = ?, error = NULL WHERE id = ?",
        [error, id],
      );

  Future<void> markFailed(int id, String error) => _db.rawUpdate(
        "UPDATE items SET status = 'failed', attempts = attempts + 1, error = ?, resume_error = NULL WHERE id = ?",
        [error, id],
      );

  Future<void> markSent(int id) => _db.rawUpdate(
        "UPDATE items SET status = 'sent', sent_at = ?, error = NULL, resume_error = NULL, path = NULL WHERE id = ?",
        [_now, id],
      );

  Future<void> retryFailed() =>
      _db.rawUpdate("UPDATE items SET status = 'queued', error = NULL, resume_error = NULL WHERE status = 'failed'");

  Future<void> resolveDuplicate(int id, String action) => _db.rawUpdate(
        "UPDATE items SET status = 'queued', duplicate_action = ?, error = NULL WHERE id = ? AND status = 'failed'",
        [action, id],
      );

  Future<void> resolveResume(int id) => _db.rawUpdate(
        "UPDATE items SET status = 'queued', resume_error = NULL, error = NULL WHERE id = ? AND status = 'failed'",
        [id],
      );

  Future<void> delete(int id) => _db.delete('items', where: 'id = ?', whereArgs: [id]);

  /// Keep the 200 most recent sent items.
  Future<void> pruneSent() => _db.rawDelete(
        "DELETE FROM items WHERE status = 'sent' AND id NOT IN "
        "(SELECT id FROM items WHERE status = 'sent' ORDER BY sent_at DESC LIMIT 200)",
      );
}
