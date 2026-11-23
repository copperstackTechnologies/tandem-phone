import 'dart:convert';

/// A paired PC. [fingerprint] is the SHA-256 of its certificate (colon-separated hex).
class Pairing {
  const Pairing({
    required this.pcName,
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.token,
  });

  final String pcName;
  final String host;
  final int port;
  final String fingerprint;
  final String token;

  Pairing withEndpoint(String host, int port) => Pairing(
    pcName: pcName,
    host: host,
    port: port,
    fingerprint: fingerprint,
    token: token,
  );

  Map<String, Object?> toJson() => {
    'pcName': pcName,
    'host': host,
    'port': port,
    'fingerprint': fingerprint,
    'token': token,
  };

  factory Pairing.fromJson(Map<String, dynamic> j) => Pairing(
    pcName: j['pcName'] as String,
    host: j['host'] as String,
    port: j['port'] as int,
    fingerprint: j['fingerprint'] as String,
    token: j['token'] as String,
  );
}

/// The JSON the desktop app puts in its pairing QR code: {v, n, h, p, s, f}.
class QrPayload {
  const QrPayload({
    required this.pcName,
    required this.host,
    required this.port,
    required this.secret,
    required this.fingerprint,
  });

  final String pcName;
  final String host;
  final int port;
  final String secret;
  final String fingerprint;

  static final _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static final _secret = RegExp(r'^[0-9a-f]{16,64}$');
  static final _fp = RegExp(r'^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$');

  /// Returns null for anything that is not a valid Tandem pairing code.
  static QrPayload? tryParse(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final v = j['v'],
          n = j['n'],
          h = j['h'],
          p = j['p'],
          s = j['s'],
          f = j['f'];
      if (v != 1 ||
          n is! String ||
          h is! String ||
          p is! int ||
          s is! String ||
          f is! String) {
        return null;
      }
      if (!_ipv4.hasMatch(h) || p < 1 || p > 65535) return null;
      if (!_secret.hasMatch(s) || !_fp.hasMatch(f)) return null;
      return QrPayload(pcName: n, host: h, port: p, secret: s, fingerprint: f);
    } catch (_) {
      return null;
    }
  }
}

enum ItemKind { file, link }

enum ItemStatus { queued, sending, sent, failed }

class QueueItem {
  const QueueItem({
    this.id,
    required this.kind,
    required this.name,
    this.path,
    this.url,
    this.size,
    this.status = ItemStatus.queued,
    this.attempts = 0,
    this.error,
    this.resumeError,
    this.targetFingerprint,
    this.relativePath,
    this.temporary = false,
    this.duplicateAction,
    required this.createdAt,
    this.sentAt,
  });

  final int? id;
  final ItemKind kind;
  final String name;
  final String? path; // copy in the app's outbox; cleared once sent
  final String? url;
  final int? size;
  final ItemStatus status;
  final int attempts;
  final String? error;
  final String? resumeError;
  final String? targetFingerprint;
  final String? relativePath;
  final bool temporary;
  final String? duplicateAction;
  final DateTime createdAt;
  final DateTime? sentAt;

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'kind': kind.name,
    'name': name,
    'path': path,
    'url': url,
    'size': size,
    'status': status.name,
    'attempts': attempts,
    'error': error,
    'resume_error': resumeError,
    'target_fingerprint': targetFingerprint,
    'relative_path': relativePath,
    'temporary': temporary ? 1 : 0,
    'duplicate_action': duplicateAction,
    'created_at': createdAt.millisecondsSinceEpoch,
    'sent_at': sentAt?.millisecondsSinceEpoch,
  };

  factory QueueItem.fromMap(Map<String, Object?> m) => QueueItem(
    id: m['id'] as int,
    kind: ItemKind.values.byName(m['kind'] as String),
    name: m['name'] as String,
    path: m['path'] as String?,
    url: m['url'] as String?,
    size: m['size'] as int?,
    status: ItemStatus.values.byName(m['status'] as String),
    attempts: m['attempts'] as int,
    error: m['error'] as String?,
    resumeError: m['resume_error'] as String?,
    targetFingerprint: m['target_fingerprint'] as String?,
    relativePath: m['relative_path'] as String?,
    temporary: (m['temporary'] as int? ?? 0) == 1,
    duplicateAction: m['duplicate_action'] as String?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    sentAt: m['sent_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(m['sent_at'] as int),
  );
}

enum PresentationAction { next, prev, start, exit }

enum MediaAction { playPause, next, prev, volumeUp, volumeDown, mute }

enum PowerAction { lock, sleep, shutdown, cancelShutdown }

class BatteryInfo {
  const BatteryInfo({
    required this.hasBattery,
    this.percent,
    this.isCharging = false,
  });
  final bool hasBattery;
  final int? percent;
  final bool isCharging;

  factory BatteryInfo.fromJson(Map<String, dynamic> j) => BatteryInfo(
    hasBattery: j['hasBattery'] as bool? ?? false,
    percent: j['percent'] as int?,
    isCharging: j['isCharging'] as bool? ?? false,
  );
}

class DiskInfo {
  const DiskInfo({
    required this.root,
    required this.totalBytes,
    required this.freeBytes,
    required this.usedBytes,
    required this.percentUsed,
  });
  final String root;
  final int totalBytes;
  final int freeBytes;
  final int usedBytes;
  final int percentUsed;

  factory DiskInfo.fromJson(Map<String, dynamic> j) => DiskInfo(
    root: j['root'] as String? ?? '',
    totalBytes: (j['totalBytes'] as num?)?.toInt() ?? 0,
    freeBytes: (j['freeBytes'] as num?)?.toInt() ?? 0,
    usedBytes: (j['usedBytes'] as num?)?.toInt() ?? 0,
    percentUsed: (j['percentUsed'] as num?)?.toInt() ?? 0,
  );
}

class ShutdownInfo {
  const ShutdownInfo({
    required this.active,
    required this.remainingSeconds,
    this.totalSeconds,
  });
  final bool active;
  final int remainingSeconds;
  final int? totalSeconds;

  factory ShutdownInfo.fromJson(Map<String, dynamic> j) => ShutdownInfo(
    active: j['active'] as bool? ?? false,
    remainingSeconds: (j['remainingSeconds'] as num?)?.toInt() ?? 0,
    totalSeconds: (j['totalSeconds'] as num?)?.toInt(),
  );
}

class PcStatus {
  const PcStatus({
    required this.pcName,
    required this.battery,
    required this.disk,
    required this.shutdown,
    this.volume = 70,
    required this.ip,
    required this.port,
    required this.itemsCount,
    this.cpuPercent,
    this.ramUsedBytes,
    this.ramTotalBytes,
    this.temperatureC,
  });
  final String pcName;
  final BatteryInfo battery;
  final DiskInfo disk;
  final ShutdownInfo shutdown;
  final int volume;
  final String ip;
  final int port;
  final int itemsCount;
  final double? cpuPercent;
  final int? ramUsedBytes;
  final int? ramTotalBytes;
  final double? temperatureC;

  factory PcStatus.fromJson(Map<String, dynamic> j) => PcStatus(
    pcName: j['pcName'] as String? ?? 'PC',
    battery: BatteryInfo.fromJson(
      (j['battery'] as Map<String, dynamic>?) ?? {},
    ),
    disk: DiskInfo.fromJson((j['disk'] as Map<String, dynamic>?) ?? {}),
    shutdown: ShutdownInfo.fromJson(
      (j['shutdown'] as Map<String, dynamic>?) ?? {},
    ),
    volume: (j['volume'] as num?)?.toInt() ?? 70,
    ip: ((j['network'] as Map<String, dynamic>?)?['ip'] as String?) ?? '',
    port:
        ((j['network'] as Map<String, dynamic>?)?['port'] as num?)?.toInt() ??
        0,
    itemsCount: (j['itemsCount'] as num?)?.toInt() ?? 0,
    cpuPercent: (j['cpuPercent'] as num?)?.toDouble(),
    ramUsedBytes: (j['ramUsedBytes'] as num?)?.toInt(),
    ramTotalBytes: (j['ramTotalBytes'] as num?)?.toInt(),
    temperatureC: (j['temperatureC'] as num?)?.toDouble(),
  );
}

class LauncherItem {
  const LauncherItem({
    required this.id,
    required this.name,
    required this.path,
    this.type = 'app',
    this.icon = 'app',
  });
  final String id;
  final String name;
  final String path;
  final String type;
  final String icon;

  factory LauncherItem.fromJson(Map<String, dynamic> j) => LauncherItem(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    path: j['path'] as String? ?? '',
    type: j['type'] as String? ?? 'app',
    icon: j['icon'] as String? ?? 'app',
  );
}

class MacroItem {
  const MacroItem({
    required this.id,
    required this.name,
    this.icon = 'work',
    this.items = const [],
  });
  final String id;
  final String name;
  final String icon;
  final List<String> items;

  factory MacroItem.fromJson(Map<String, dynamic> j) => MacroItem(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    icon: j['icon'] as String? ?? 'work',
    items: (j['items'] as List?)?.whereType<String>().toList() ?? const [],
  );
}

class ApprovedFolder {
  const ApprovedFolder({
    required this.id,
    required this.name,
    required this.path,
    this.icon = 'folder',
  });
  final String id;
  final String name;
  final String path;
  final String icon;

  factory ApprovedFolder.fromJson(Map<String, dynamic> j) => ApprovedFolder(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    path: j['path'] as String? ?? '',
    icon: j['icon'] as String? ?? 'folder',
  );
}

class RemoteFileEntry {
  const RemoteFileEntry({
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.mtime,
    required this.ext,
    required this.relPath,
  });
  final String name;
  final bool isDirectory;
  final int size;
  final String mtime;
  final String ext;
  final String relPath;

  factory RemoteFileEntry.fromJson(Map<String, dynamic> j) => RemoteFileEntry(
    name: j['name'] as String? ?? '',
    isDirectory: j['isDirectory'] as bool? ?? false,
    size: (j['size'] as num?)?.toInt() ?? 0,
    mtime: j['mtime'] as String? ?? '',
    ext: j['ext'] as String? ?? '',
    relPath: j['relPath'] as String? ?? '',
  );
}

enum ClipboardOrigin { phone, pc }

class ClipboardItem {
  const ClipboardItem({
    required this.id,
    required this.text,
    required this.origin,
    required this.timestamp,
  });

  final String id;
  final String text;
  final ClipboardOrigin origin;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'origin': origin.name,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory ClipboardItem.fromJson(Map<String, dynamic> j) => ClipboardItem(
    id: j['id'] as String? ?? '',
    text: j['text'] as String? ?? '',
    origin: (j['origin'] as String? ?? 'phone') == 'pc'
        ? ClipboardOrigin.pc
        : ClipboardOrigin.phone,
    timestamp: DateTime.fromMillisecondsSinceEpoch(
      (j['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    ),
  );
}
