import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'db.dart';
import 'models.dart';
import 'pc_client.dart';
import 'storage.dart';

enum FlushResult { notPaired, idle, done, unreachable, unauthorized }

/// Queue logic shared by the app and the background worker (no UI imports).
class Uploader {
  Uploader({required this.db, required this.store});

  final Db db;
  final PairingStore store;

  /// Called whenever a row changed, and with upload progress for the item being sent.
  void Function()? onChanged;
  void Function(int id, int sent, int total)? onProgress;

  bool _running = false;
  final Map<int, CancelToken> _cancels = {};

  Future<Directory> _outbox() async {
    final base = await getApplicationSupportDirectory();
    return Directory(p.join(base.path, 'outbox')).create(recursive: true);
  }

  // ---- enqueue -------------------------------------------------------------

  /// Copies the file into the app's outbox so it survives until it is sent.
  Future<int> enqueueFile(String src, {String? targetFingerprint, String? relativePath, bool temporary = false}) async {
    final f = File(src);
    if (!await f.exists()) throw FileSystemException('File not found', src);
    final name = p.basename(src);
    final dest = p.join((await _outbox()).path, '${DateTime.now().microsecondsSinceEpoch}_$name');
    await f.copy(dest);
    return db.insert(QueueItem(
      kind: ItemKind.file,
      name: name,
      path: dest,
      size: await File(dest).length(),
      targetFingerprint: targetFingerprint,
      relativePath: relativePath,
      temporary: temporary,
      createdAt: DateTime.now(),
    ));
  }

  /// For files that have no local path (e.g. picked through the system document picker).
  Future<int> enqueueStream(String name, Stream<List<int>> data, {String? targetFingerprint, bool temporary = false}) async {
    final safe = p.basename(name);
    final dest = p.join((await _outbox()).path, '${DateTime.now().microsecondsSinceEpoch}_$safe');
    final sink = File(dest).openWrite();
    try {
      await sink.addStream(data);
    } finally {
      await sink.close();
    }
    return db.insert(QueueItem(
      kind: ItemKind.file,
      name: safe,
      path: dest,
      size: await File(dest).length(),
      targetFingerprint: targetFingerprint,
      temporary: temporary,
      createdAt: DateTime.now(),
    ));
  }

  Future<int> enqueueLink(String url, {String? title}) => db.insert(QueueItem(
        kind: ItemKind.link,
        name: (title == null || title.isEmpty) ? (Uri.tryParse(url)?.host ?? url) : title,
        url: url,
        createdAt: DateTime.now(),
      ));

  /// Shared plain text (no link in it) is saved on the PC as a .txt file.
  Future<int> enqueueText(String text) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'Note ${now.year}-${two(now.month)}-${two(now.day)} ${two(now.hour)}-${two(now.minute)}-${two(now.second)}.txt';
    final dest = p.join((await _outbox()).path, '${now.microsecondsSinceEpoch}_$name');
    final file = File(dest);
    await file.writeAsString(text);
    return db.insert(QueueItem(
      kind: ItemKind.file,
      name: name,
      path: dest,
      size: await file.length(),
      createdAt: now,
    ));
  }

  // ---- connect -------------------------------------------------------------

  /// Tries the last known address, then looks the PC up on the network.
  /// Returns null if it cannot be reached. Throws [PcException] with kind unauthorized if the PC revoked this phone.
  Future<PcClient?> connect(Pairing pairing, {bool discover = true}) async {
    bool retriable(PcException e) => e.kind == PcFailure.unreachable || e.kind == PcFailure.certMismatch;

    var client = PcClient.forPairing(pairing);
    try {
      await client.ping();
      return client;
    } on PcException catch (e) {
      if (!retriable(e)) rethrow;
    }
    if (!discover) return null;

    final found = await discoverPc(pairing.fingerprint);
    if (found == null) return null;
    final moved = pairing.withEndpoint(found.host, found.port);
    client = PcClient.forPairing(moved);
    try {
      await client.ping();
    } on PcException catch (e) {
      if (retriable(e)) return null;
      rethrow;
    }
    await store.updateEndpoint(moved); // remember without switching the selected PC
    return client;
  }

  // ---- send ----------------------------------------------------------------

  Future<FlushResult> flush() async {
    if (_running) return FlushResult.idle;
    _running = true;
    try {
      final selectedPairing = await store.load();
      if (selectedPairing == null) return FlushResult.notPaired;
      final pairings = await store.loadAll();
      await db.resetStuck();
      final pending = await db.byStatus([ItemStatus.queued]);
      if (pending.isEmpty) return FlushResult.idle;
      var sawUnreachable = false;

      for (final item in pending) {
        final pairing = item.targetFingerprint == null
            ? selectedPairing
            : _findPairing(pairings, item.targetFingerprint!);
        if (pairing == null) {
          await db.markFailed(item.id!, 'The selected PC is no longer paired.');
          onChanged?.call();
          continue;
        }
        final PcClient? client;
        try {
          client = await connect(pairing);
        } on PcException catch (e) {
          if (e.kind == PcFailure.unauthorized) {
            await db.markFailed(item.id!, e.message);
            onChanged?.call();
          } else if (e.kind == PcFailure.unreachable || e.kind == PcFailure.certMismatch) {
            sawUnreachable = true;
          } else {
            await db.markFailed(item.id!, e.message);
            onChanged?.call();
          }
          continue;
        }
        if (client == null) {
          sawUnreachable = true;
          continue;
        }
        final id = item.id!;
        if (!await db.claim(id)) continue; // another flusher took it
        onChanged?.call();
        try {
          if (item.kind == ItemKind.link) {
            await client.sendLink(item.url!, item.name);
          } else {
            final path = item.path;
            if (path == null || !await File(path).exists()) {
              await db.markFailed(id, 'The file is no longer available.');
              onChanged?.call();
              continue;
            }
            final ct = _cancels[id] = CancelToken();
            await client.upload(path, item.name,
                transferId: id.toString(), temporary: item.temporary, relativePath: item.relativePath,
                duplicateAction: item.duplicateAction,
                cancel: ct, onProgress: (s, t) => onProgress?.call(id, s, t));
            _cancels.remove(id);
            try {
              await File(path).delete();
            } catch (_) {}
          }
          await db.markSent(id);
        } on FileSystemException {
          _cancels.remove(id);
          await db.markFailed(id, 'The file could not be read.');
        } on PcException catch (e) {
          _cancels.remove(id);
          if (e.kind == PcFailure.cancelled) continue; // removed by the user
          if (e.kind == PcFailure.unreachable || e.kind == PcFailure.certMismatch) {
            await db.requeue(id, e.message);
            onChanged?.call();
            sawUnreachable = true;
            continue;
          }
          if (e.kind == PcFailure.unauthorized) {
            await db.requeue(id, e.message);
            onChanged?.call();
            await db.markFailed(id, e.message);
            onChanged?.call();
            continue;
          }
          await db.markFailed(id, e.message);
        }
        onChanged?.call();
      }
      await db.pruneSent();
      return sawUnreachable ? FlushResult.unreachable : FlushResult.done;
    } finally {
      _running = false;
    }
  }

  Pairing? _findPairing(List<Pairing> pairings, String fingerprint) {
    final target = fingerprint.replaceAll(':', '').toLowerCase();
    for (final pairing in pairings) {
      if (pairing.fingerprint.replaceAll(':', '').toLowerCase() == target) {
        return pairing;
      }
    }
    return null;
  }

  /// Removes an item (cancelling its upload if it is in flight) and deletes its outbox copy.
  Future<void> remove(int id) async {
    _cancels.remove(id)?.cancel();
    final item = await db.get(id);
    final path = item?.path;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    await db.delete(id);
    onChanged?.call();
  }
}
