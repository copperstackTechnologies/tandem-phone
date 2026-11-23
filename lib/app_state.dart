import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background.dart';
import 'db.dart';
import 'models.dart';
import 'pc_client.dart';
import 'storage.dart';
import 'uploader.dart';
import 'util.dart';

enum Conn { unknown, checking, connected, unreachable, revoked }

class EnqueueResult {
  const EnqueueResult(this.ids, this.skipped);
  final List<int> ids;
  final int skipped;
}

class AppState extends ChangeNotifier {
  AppState._(
    this.db,
    this.store,
    this.uploader,
    this.settings,
    this.pairing,
    this.pairings,
  );
  static const _appUpdateChannel = MethodChannel('com.tandem.app/app_updates');
  static const _phoneUpdatesUrl =
      'https://github.com/copperstackTechnologies/tandem-phone/releases/latest/download/latest.json';

  final Db db;
  final PairingStore store;
  final Uploader uploader;
  final Settings settings;
  Pairing? pairing;
  List<Pairing> pairings;

  Conn conn = Conn.unknown;
  PcStatus? lastStatus;
  List<QueueItem> items = const [];
  List<File> receivedFromPc = [];
  List<Map<String, dynamic>> waitingFromPc = [];
  bool _receivingPcFiles = false;
  final Map<int, double> progress = {};
  StreamSubscription<List<ConnectivityResult>>? _net;
  bool _checkingConnection = false;
  List<ClipboardItem> clipboardHistory = [];
  List<String> remoteCardOrder = ['presentation', 'media', 'clipboard'];

  static Future<AppState> create() async {
    final db = await Db.open();
    final store = PairingStore();
    final pairings = await store.loadAll();
    final state = AppState._(
      db,
      store,
      Uploader(db: db, store: store),
      await Settings.load(),
      await store.load(),
      pairings,
    );
    state.uploader.onChanged = state.refresh;
    state.uploader.onProgress = state._onProgress;
    await state.loadClipboardAndCardOrder();
    if (Platform.isAndroid) unawaited(state.checkPhoneAppUpdates());
    return state;
  }

  Future<void> loadClipboardAndCardOrder() async {
    final p = await SharedPreferences.getInstance();
    final rawClip = p.getStringList('clipboard_history');
    if (rawClip != null) {
      clipboardHistory = rawClip
          .map((s) {
            try {
              return ClipboardItem.fromJson(
                jsonDecode(s) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<ClipboardItem>()
          .toList();
    }
    final rawOrder = p.getStringList('remote_card_order');
    if (rawOrder != null && rawOrder.isNotEmpty) {
      const valid = ['presentation', 'media', 'clipboard'];
      final saved = rawOrder.where((k) => valid.contains(k)).toList();
      for (final v in valid) {
        if (!saved.contains(v)) saved.add(v);
      }
      remoteCardOrder = saved;
    }
    notifyListeners();
  }

  Future<void> setRemoteCardOrder(List<String> order) async {
    remoteCardOrder = List<String>.from(order);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setStringList('remote_card_order', remoteCardOrder);
  }

  Future<void> addClipboardItem(String text, ClipboardOrigin origin) async {
    if (text.trim().isEmpty) return;
    clipboardHistory.removeWhere((item) => item.text == text);
    clipboardHistory.insert(
      0,
      ClipboardItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        origin: origin,
        timestamp: DateTime.now(),
      ),
    );
    if (clipboardHistory.length > 50) {
      clipboardHistory = clipboardHistory.sublist(0, 50);
    }
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    final encoded = clipboardHistory
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    await p.setStringList('clipboard_history', encoded);
  }

  Future<void> removeClipboardItem(String id) async {
    clipboardHistory.removeWhere((item) => item.id == id);
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    final encoded = clipboardHistory
        .map((item) => jsonEncode(item.toJson()))
        .toList();
    await p.setStringList('clipboard_history', encoded);
  }

  Future<void> clearClipboardHistory() async {
    clipboardHistory.clear();
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove('clipboard_history');
  }

  Future<void> checkPhoneClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        if (clipboardHistory.isEmpty || clipboardHistory.first.text != text) {
          await addClipboardItem(text, ClipboardOrigin.phone);
        }
      }
    } catch (_) {}
  }

  void _onProgress(int id, int sent, int total) {
    progress[id] = total > 0 ? sent / total : 0.0;
    notifyListeners();
  }

  List<QueueItem> get waiting =>
      items.where((i) => i.status != ItemStatus.sent).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  List<QueueItem> get sent =>
      items.where((i) => i.status == ItemStatus.sent).toList()
        ..sort((a, b) => b.sentAt!.compareTo(a.sentAt!));

  Future<void> refresh() async {
    final waiting = await db.byStatus([
      ItemStatus.queued,
      ItemStatus.sending,
      ItemStatus.failed,
    ]);
    final sent = await db.byStatus(
      [ItemStatus.sent],
      order: 'sent_at DESC',
      limit: 50,
    );
    items = [...waiting, ...sent];
    progress.removeWhere((id, _) => !waiting.any((i) => i.id == id));
    notifyListeners();
  }

  /// Call once at launch.
  Future<void> start() async {
    await db.resetStuck();
    await refresh();
    _net = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none) && waiting.isNotEmpty) sync();
    });
    await _syncBackground();
    await sync();
    if (pairing != null) await checkConnection();
  }

  Future<void> onResume() async {
    await checkPhoneClipboard();
    await sync();
  }

  /// Sends whatever is waiting; if nothing is, just checks that the PC is reachable.
  Future<void> sync() async {
    if (pairing == null) return;
    final r = await uploader.flush();
    switch (r) {
      case FlushResult.done:
        conn = Conn.connected;
      case FlushResult.unreachable:
        conn = Conn.unreachable;
      case FlushResult.unauthorized:
        conn = Conn.revoked;
      case FlushResult.idle:
        return;
      case FlushResult.notPaired:
        break;
    }
    await refresh();
  }

  /// Pings the PC and updates [conn].
  Future<void> checkConnection() async {
    final p = pairing;
    if (p == null || _checkingConnection) return;
    _checkingConnection = true;
    conn = Conn.checking;
    notifyListeners();
    try {
      final client = await uploader.connect(p);
      if (pairing?.fingerprint != p.fingerprint) return;
      conn = client == null ? Conn.unreachable : Conn.connected;
      if (client != null) {
        pairing = await store.load(); // address may have changed
        pairings = await store.loadAll();
        unawaited(checkForUpdates());
        unawaited(_receiveFilesFromPc(client));
      }
    } on PcException catch (e) {
      if (pairing?.fingerprint != p.fingerprint) return;
      conn = e.kind == PcFailure.unauthorized ? Conn.revoked : Conn.unreachable;
    } finally {
      _checkingConnection = false;
      notifyListeners();
    }
  }

  Future<void> _receiveFilesFromPc(PcClient client) async {
    if (_receivingPcFiles) return;
    _receivingPcFiles = true;
    try {
      final incoming = await client.getPhoneInbox();
      if (incoming.isEmpty) return;
      final documents = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(documents.path, 'Tandem_Downloads'));
      await directory.create(recursive: true);
      final prefs = await SharedPreferences.getInstance();
      final received = <File>[];
      for (final item in incoming) {
        final id = item['id'] as String?;
        final name = item['name'] as String?;
        if (id == null || name == null) continue;
        final receiptKey = 'pc_inbox_receipt_$id';
        final existingReceipt = prefs.getString(receiptKey);
        if (existingReceipt != null && await File(existingReceipt).exists()) {
          await client.acknowledgePhoneInboxFile(id);
          await prefs.remove(receiptKey);
          continue;
        }
        final existing = File(p.join(directory.path, p.basename(name)));
        if (await existing.exists()) {
          if (!waitingFromPc.any((queued) => queued['id'] == id)) {
            waitingFromPc = [...waitingFromPc, item];
            notifyListeners();
          }
          continue;
        }
        final saved = await _downloadPcInboxItem(client, directory, item, 'rename');
        if (saved != null) received.add(saved);
      }
      if (received.isNotEmpty) {
        receivedFromPc = [...received, ...receivedFromPc].take(10).toList();
        notifyListeners();
      }
    } catch (_) {
      // Inbox delivery retries when the user checks the connection again.
    } finally {
      _receivingPcFiles = false;
    }
  }

  Future<void> resolvePcInboxDuplicate(String id, String action) async {
    Map<String, dynamic>? item;
    for (final queued in waitingFromPc) {
      if (queued['id'] == id) { item = queued; break; }
    }
    if (item == null) return;
    final client = await getClient();
    if (client == null) return;
    if (action == 'skip') {
      await client.acknowledgePhoneInboxFile(id);
      final documents = await getApplicationDocumentsDirectory();
      final partial = File(p.join(documents.path, 'Tandem_Downloads', '.tandem-$id.part'));
      if (await partial.exists()) await partial.delete();
      waitingFromPc = waitingFromPc.where((value) => value['id'] != id).toList();
      notifyListeners();
      return;
    }
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(documents.path, 'Tandem_Downloads'));
    await directory.create(recursive: true);
    final saved = await _downloadPcInboxItem(client, directory, item, action);
    if (saved != null) {
      waitingFromPc = waitingFromPc.where((value) => value['id'] != id).toList();
      receivedFromPc = [saved, ...receivedFromPc].take(10).toList();
      notifyListeners();
    }
  }

  Future<void> openReceivedFile(File file) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('Opening received files from Tandem is currently supported on Android.');
    }
    await _appUpdateChannel.invokeMethod<void>('openReceivedFile', {'path': file.path});
  }

  Future<File?> _downloadPcInboxItem(
    PcClient client,
    Directory directory,
    Map<String, dynamic> item,
    String duplicateAction,
  ) async {
    final id = item['id'] as String;
    final name = item['name'] as String;
    final size = (item['size'] as num?)?.toInt() ?? 0;
    final partial = File(p.join(directory.path, '.tandem-$id.part'));
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset > size) {
      await partial.delete();
      offset = 0;
    }
    if (offset < size) {
      await client.downloadPhoneInboxFile(id, partial.path, offset: offset);
    }
    if (!await partial.exists() || await partial.length() != size) return null;
    final target = duplicateAction == 'replace'
        ? File(p.join(directory.path, p.basename(name)))
        : _uniqueLocalFile(directory.path, name);
    if (duplicateAction == 'replace' && await target.exists()) await target.delete();
    final saved = await partial.rename(target.path);
    final prefs = await SharedPreferences.getInstance();
    final receiptKey = 'pc_inbox_receipt_$id';
    await prefs.setString(receiptKey, saved.path);
    await client.acknowledgePhoneInboxFile(id);
    await prefs.remove(receiptKey);
    return saved;
  }

  File _uniqueLocalFile(String directory, String name) {
    final safe = p.basename(name).replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_');
    final extension = p.extension(safe);
    final stem = p.basenameWithoutExtension(safe);
    var result = File(p.join(directory, safe));
    var index = 1;
    while (result.existsSync()) {
      result = File(p.join(directory, '$stem ($index)$extension'));
      index++;
    }
    return result;
  }

  // ---- adding things to send ----------------------------------------------

  Future<EnqueueResult> enqueueShared(List<SharedMediaFile> media) async {
    final ids = <int>[];
    var skipped = 0;
    for (final m in media) {
      try {
        if (m.type == SharedMediaType.text || m.type == SharedMediaType.url) {
          final url = firstUrl(m.path);
          if (url != null) {
            ids.add(
              await uploader.enqueueLink(
                url,
                title: m.path.replaceAll(url, '').trim(),
              ),
            );
          } else {
            ids.add(await uploader.enqueueText(m.path));
          }
        } else {
          ids.add(await uploader.enqueueFile(m.path));
        }
      } catch (_) {
        skipped++;
      }
    }
    await refresh();
    return EnqueueResult(ids, skipped);
  }

  Future<void> addPicked(
    List<PlatformFile> files, {
    List<String>? targetFingerprints,
    bool temporary = false,
  }) async {
    final targets = targetFingerprints ?? [if (pairing != null) pairing!.fingerprint];
    if (targets.isEmpty) return;
    for (final f in files) {
      for (final target in targets) {
        try {
          await uploader.enqueueStream(
            f.name,
            f.readAsByteStream(),
            targetFingerprint: target,
            temporary: temporary,
          );
        } catch (_) {}
      }
    }
    await refresh();
    unawaited(sync());
  }

  Future<void> addFolder(
    String folderPath, {
    List<String>? targetFingerprints,
    bool temporary = false,
  }) async {
    final targets = targetFingerprints ?? [if (pairing != null) pairing!.fingerprint];
    if (targets.isEmpty) return;
    final root = Directory(folderPath);
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p.join(p.basename(folderPath), p.relative(entity.path, from: folderPath));
      for (final target in targets) {
        try {
          await uploader.enqueueFile(
            entity.path,
            targetFingerprint: target,
            relativePath: relative,
            temporary: temporary,
          );
        } catch (_) {}
      }
    }
    await refresh();
    unawaited(sync());
  }

  Future<void> addLink(String url) async {
    await uploader.enqueueLink(url);
    await refresh();
    unawaited(sync());
  }

  Future<void> retryAll() async {
    await db.retryFailed();
    await refresh();
    await sync();
  }

  Future<void> removeItem(int id) => uploader.remove(id);

  Future<void> resolveDuplicate(int id, String action) async {
    if (action == 'skip') {
      await uploader.remove(id);
    } else {
      await db.resolveDuplicate(id, action);
      await refresh();
      unawaited(sync());
    }
  }

  Future<void> resumeTransfer(int id) async {
    await db.resolveResume(id);
    await refresh();
    unawaited(sync());
  }

  // ---- pairing -------------------------------------------------------------

  Future<String> _deviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await info.androidInfo;
        return '${a.manufacturer} ${a.model}';
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return (await info.iosInfo).name;
      }
    } catch (_) {}
    return 'Phone';
  }

  /// Pairs with the PC shown in the QR code. Throws [PcException] with a message fit for the user.
  Future<void> pairWith(QrPayload q) async {
    final r = await PcClient.pair(q, await _deviceName());
    final p = Pairing(
      pcName: r.pcName,
      host: r.host,
      port: r.port,
      fingerprint: q.fingerprint,
      token: r.token,
    );
    await store.save(p);
    pairings = await store.loadAll();
    pairing = p;
    conn = Conn.connected;
    await _syncBackground();
    notifyListeners();
    unawaited(sync()); // anything shared before pairing goes out now
  }

  Future<void> unpair() async {
    final p = pairing;
    if (p != null) {
      try {
        await PcClient.forPairing(p).unpair(); // tell the PC if it is reachable
      } catch (_) {}
    }
    if (p != null) await store.remove(p);
    pairings = await store.loadAll();
    pairing = await store.load();
    conn = pairing == null ? Conn.unknown : Conn.checking;
    await _syncBackground();
    notifyListeners();
    if (pairing != null) unawaited(sync());
  }

  Future<void> selectPairing(Pairing selected) async {
    if (pairing?.fingerprint == selected.fingerprint) return;
    await store.select(selected);
    pairing = selected;
    lastStatus = null;
    conn = Conn.checking;
    notifyListeners();
    await _syncBackground();
    await sync();
  }

  // ---- settings ------------------------------------------------------------

  Future<void> setBackgroundSend(bool v) async {
    settings.backgroundSend = v;
    await settings.save();
    await _syncBackground();
    notifyListeners();
  }

  Future<void> setCloseAfterShare(bool v) async {
    settings.closeAfterShare = v;
    await settings.save();
    notifyListeners();
  }

  Future<void> _syncBackground() async {
    try {
      await scheduleBackgroundFlush(settings.backgroundSend && pairing != null);
    } catch (_) {
      // Background scheduling is best effort.
    }
  }

  // ---- PC remote & companion controls ------------------------------------

  Future<PcClient?> getClient() async {
    final p = pairing;
    if (p == null) return null;
    final client = await uploader.connect(p);
    if (client != null) {
      pairing = await store.load();
      pairings = await store.loadAll();
    }
    return client;
  }

  Future<PcStatus?> fetchStatus() async {
    final client = await getClient();
    if (client == null) return null;
    try {
      lastStatus = await client.getStatus();
      conn = Conn.connected;
      notifyListeners();
      unawaited(_receiveFilesFromPc(client));
      return lastStatus;
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendPresentation(PresentationAction action) async {
    final client = await getClient();
    if (client == null) return false;
    await client.sendPresentation(action);
    return true;
  }

  Future<bool> sendMedia(MediaAction action) async {
    final client = await getClient();
    if (client == null) return false;
    await client.sendMedia(action);
    return true;
  }

  Future<bool> setVolume(int volumePercent) async {
    final client = await getClient();
    if (client == null) return false;
    await client.setVolume(volumePercent);
    if (lastStatus != null) {
      lastStatus = PcStatus(
        pcName: lastStatus!.pcName,
        battery: lastStatus!.battery,
        disk: lastStatus!.disk,
        shutdown: lastStatus!.shutdown,
        volume: volumePercent,
        ip: lastStatus!.ip,
        port: lastStatus!.port,
        itemsCount: lastStatus!.itemsCount,
        cpuPercent: lastStatus!.cpuPercent,
        ramUsedBytes: lastStatus!.ramUsedBytes,
        ramTotalBytes: lastStatus!.ramTotalBytes,
        temperatureC: lastStatus!.temperatureC,
      );
      notifyListeners();
    }
    return true;
  }

  Future<ShutdownInfo?> sendPower(
    PowerAction action, {
    int? delaySeconds,
  }) async {
    final client = await getClient();
    if (client == null) return null;
    final info = await client.sendPower(action, delaySeconds: delaySeconds);
    if (lastStatus != null) {
      lastStatus = PcStatus(
        pcName: lastStatus!.pcName,
        battery: lastStatus!.battery,
        disk: lastStatus!.disk,
        shutdown: info,
        volume: lastStatus!.volume,
        ip: lastStatus!.ip,
        port: lastStatus!.port,
        itemsCount: lastStatus!.itemsCount,
        cpuPercent: lastStatus!.cpuPercent,
        ramUsedBytes: lastStatus!.ramUsedBytes,
        ramTotalBytes: lastStatus!.ramTotalBytes,
        temperatureC: lastStatus!.temperatureC,
      );
      notifyListeners();
    }
    return info;
  }

  Future<String?> pullClipboard() async {
    final client = await getClient();
    if (client == null) return null;
    final text = await client.getClipboard();
    if (text.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: text));
      await addClipboardItem(text, ClipboardOrigin.pc);
    }
    return text;
  }

  Future<bool> pushClipboard(String text) async {
    final client = await getClient();
    if (client == null) return false;
    await client.setClipboard(text);
    await addClipboardItem(text, ClipboardOrigin.phone);
    return true;
  }

  Future<bool> openLinkNow(String url, {String? title}) async {
    final client = await getClient();
    if (client == null) return false;
    await client.openLinkNow(url, title);
    await refresh();
    return true;
  }

  Future<({List<LauncherItem> launchers, List<MacroItem> macros})>
  getLaunchers() async {
    final client = await getClient();
    if (client == null) {
      return (launchers: <LauncherItem>[], macros: <MacroItem>[]);
    }
    return await client.getLaunchers();
  }

  Future<bool> runLauncher(String id) async {
    final client = await getClient();
    if (client == null) return false;
    await client.runLauncher(id);
    return true;
  }

  Future<bool> runMacro(String id) async {
    final client = await getClient();
    if (client == null) return false;
    await client.runMacro(id);
    return true;
  }

  Future<List<ApprovedFolder>> getApprovedFolders() async {
    final client = await getClient();
    if (client == null) return [];
    return await client.getApprovedFolders();
  }

  Future<
    ({String folderName, String currentPath, List<RemoteFileEntry> entries})
  >
  browseDir(String folderId, {String? subpath}) async {
    final client = await getClient();
    if (client == null) {
      return (folderName: '', currentPath: '', entries: <RemoteFileEntry>[]);
    }
    return await client.browseDir(folderId, subpath: subpath);
  }

  Map<String, dynamic>? _updateStatus;
  Map<String, dynamic>? get updateStatus => _updateStatus;
  bool get hasUpdate => _updateStatus?['updateAvailable'] == true;

  Future<Map<String, dynamic>?> checkForUpdates() async {
    try {
      final client = await getClient();
      if (client == null) return null;
      final st = await client.checkUpdate();
      _updateStatus = st;
      notifyListeners();
      return st;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _phoneAppUpdateStatus;
  Map<String, dynamic>? get phoneAppUpdateStatus => _phoneAppUpdateStatus;
  bool get hasPhoneAppUpdate =>
      _phoneAppUpdateStatus?['updateAvailable'] == true;

  Future<Map<String, dynamic>?> checkPhoneAppUpdates() async {
    if (!Platform.isAndroid) {
      _phoneAppUpdateStatus = {
        'updateAvailable': false,
        'message':
            'Phone app updates are distributed through the App Store on iOS.',
      };
      notifyListeners();
      return _phoneAppUpdateStatus;
    }

    try {
      final currentVersion =
          await _appUpdateChannel.invokeMethod<String>('getAppVersion') ??
          '0.0.0';
      final response = await Dio().get<String>(
        _phoneUpdatesUrl,
        options: Options(
          responseType: ResponseType.plain,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
        ),
      );
      final metadata = jsonDecode(response.data ?? '') as Map<String, dynamic>;
      final latestVersion = metadata['version'] as String?;
      final apkUrl = metadata['apkUrl'] as String?;
      final checksum = (metadata['sha256'] as String? ?? '').toLowerCase();
      if (latestVersion == null ||
          apkUrl == null ||
          Uri.tryParse(apkUrl)?.scheme != 'https' ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
        throw const FormatException('The phone release metadata is invalid.');
      }
      final available = _compareVersions(latestVersion, currentVersion) > 0;
      _phoneAppUpdateStatus = {
        'updateAvailable': available,
        'currentVersion': currentVersion,
        'latestVersion': latestVersion,
        'apkUrl': apkUrl,
        'sha256': checksum,
        'message': available
            ? 'Phone app update $latestVersion is available.'
            : 'Phone app is up to date.',
      };
    } catch (error) {
      _phoneAppUpdateStatus = {
        'updateAvailable': false,
        'checkFailed': true,
        'message': 'Could not check for phone app updates: $error',
      };
    }
    notifyListeners();
    return _phoneAppUpdateStatus;
  }

  int _compareVersions(String a, String b) {
    final left = a.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    final right = b.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    for (
      var i = 0;
      i < (left.length > right.length ? left.length : right.length);
      i++
    ) {
      final x = i < left.length ? left[i] : 0;
      final y = i < right.length ? right[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  Future<Map<String, dynamic>> installPhoneAppUpdate() async {
    if (!Platform.isAndroid) {
      return {
        'success': false,
        'error': 'Phone self-updates are available on Android.',
      };
    }
    final update = _phoneAppUpdateStatus;
    if (update == null || update['updateAvailable'] != true) {
      return {'success': false, 'error': 'No phone app update is available.'};
    }
    try {
      final canInstall =
          await _appUpdateChannel.invokeMethod<bool>('canInstallPackages') ??
          false;
      if (!canInstall) {
        await _appUpdateChannel.invokeMethod<void>('requestInstallPermission');
        return {
          'success': false,
          'permissionRequired': true,
          'message':
              'Allow Tandem to install apps from this source in Android settings, then tap Update again.',
        };
      }

      final temp = await getTemporaryDirectory();
      final updateDir = Directory(p.join(temp.path, 'updates'));
      await updateDir.create(recursive: true);
      final apk = File(p.join(updateDir.path, 'Tandem-update.apk'));
      await Dio().download(
        update['apkUrl'] as String,
        apk.path,
        options: Options(receiveTimeout: const Duration(minutes: 3)),
      );
      final digest = await sha256.bind(apk.openRead()).first;
      if (digest.toString() != update['sha256']) {
        await apk.delete();
        throw const FormatException(
          'The downloaded APK checksum did not match the published release.',
        );
      }
      await _appUpdateChannel.invokeMethod<void>('installApk', {
        'path': apk.path,
      });
      return {
        'success': true,
        'message':
            'Android opened the verified installer. Confirm the update to finish.',
      };
    } catch (error) {
      return {'success': false, 'error': '$error'};
    }
  }

  Future<Map<String, dynamic>?> applyUpdate() async {
    try {
      final client = await getClient();
      if (client == null) return null;
      final res = await client.applyUpdate();
      await checkForUpdates();
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<File?> fetchRemoteToCache(
    String folderId,
    RemoteFileEntry entry, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = await getClient();
    if (client == null) return null;
    final tempDir = await getTemporaryDirectory();
    final cacheDir = Directory(p.join(tempDir.path, 'tandem_preview'));
    await cacheDir.create(recursive: true);
    final safeBase = entry.name.replaceAll(RegExp(r'[^\w\.-]+'), '_');
    final cacheFile = File(p.join(cacheDir.path, '${folderId}_$safeBase'));
    if (await cacheFile.exists() &&
        (await cacheFile.length()) == entry.size &&
        entry.size > 0) {
      return cacheFile;
    }
    await client.downloadRemoteFile(
      folderId,
      entry.relPath,
      cacheFile.path,
      onProgress: onProgress,
    );
    return cacheFile;
  }

  Future<File?> downloadRemoteFile(
    String folderId,
    RemoteFileEntry entry, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = await getClient();
    if (client == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory(p.join(dir.path, 'Tandem_Downloads'));
    await saveDir.create(recursive: true);
    final targetPath = p.join(saveDir.path, entry.name);
    await client.downloadRemoteFile(
      folderId,
      entry.relPath,
      targetPath,
      onProgress: onProgress,
    );
    return File(targetPath);
  }

  @override
  void dispose() {
    _net?.cancel();
    super.dispose();
  }
}
