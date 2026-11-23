import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:nsd/nsd.dart';

import 'models.dart';

/// "AA:BB:.." (Node) and "aabb.." (Dart) compare equal after this.
String normFp(String s) => s.replaceAll(':', '').toLowerCase();

enum PcFailure { unreachable, certMismatch, unauthorized, rejected, cancelled }

class PcException implements Exception {
  PcException(this.kind, this.message);
  final PcFailure kind;
  final String message;
  @override
  String toString() => message;
}

/// HTTP client that trusts exactly one certificate: the one whose SHA-256 matches [fingerprint].
/// System root certificates are disabled, so every connection goes through the check.
Dio buildDio({
  required String host,
  required int port,
  required String fingerprint,
  String? token,
  Duration connectTimeout = const Duration(seconds: 5),
}) {
  final want = normFp(fingerprint);
  final dio = Dio(BaseOptions(
    baseUrl: 'https://$host:$port',
    connectTimeout: connectTimeout,
    receiveTimeout: const Duration(seconds: 30),
    headers: token == null ? null : {'Authorization': 'Bearer $token'},
    validateStatus: (_) => true, // status codes are handled in _check
  ));
  dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () {
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false));
    c.badCertificateCallback =
        (X509Certificate cert, String h, int p) => normFp(sha256.convert(cert.der).toString()) == want;
    return c;
  });
  return dio;
}

Future<Response<dynamic>> _call(Future<Response<dynamic>> Function() f) async {
  try {
    return await f();
  } on DioException catch (e) {
    if (e.type == DioExceptionType.cancel) throw PcException(PcFailure.cancelled, 'Cancelled');
    if (e.error is TlsException) {
      throw PcException(PcFailure.certMismatch, 'This is not the PC you paired with.');
    }
    throw PcException(PcFailure.unreachable, 'PC not reachable');
  }
}

Response<dynamic> _check(Response<dynamic> r) {
  final code = r.statusCode ?? 0;
  if (code >= 200 && code < 300) return r;
  if (code == 401) throw PcException(PcFailure.unauthorized, 'This PC no longer accepts this phone.');
  if (code == 403) {
    throw PcException(PcFailure.rejected, 'The pairing code expired or was already used. Show a new code on your PC.');
  }
  if (code == 413) throw PcException(PcFailure.rejected, 'The PC rejected the file because it is too large.');
  final d = r.data;
  final msg = d is Map && d['error'] is String ? d['error'] as String : 'PC returned error $code';
  throw PcException(PcFailure.rejected, msg);
}

class PcClient {
  PcClient(this._dio);
  final Dio _dio;

  factory PcClient.forPairing(Pairing p, {Duration connectTimeout = const Duration(seconds: 5)}) =>
      PcClient(buildDio(
        host: p.host,
        port: p.port,
        fingerprint: p.fingerprint,
        token: p.token,
        connectTimeout: connectTimeout,
      ));

  /// First-time pairing using the data from the QR code.
  /// If the direct address fails to connect, attempts local mDNS discovery as a fallback.
  static Future<({String token, String pcName, String host, int port})> pair(
      QrPayload q, String deviceName) async {
    try {
      final dio = buildDio(host: q.host, port: q.port, fingerprint: q.fingerprint);
      final r = _check(await _call(() => dio.post('/pair', data: {'secret': q.secret, 'deviceName': deviceName})));
      final d = r.data as Map;
      return (token: d['token'] as String, pcName: d['pcName'] as String, host: q.host, port: q.port);
    } on PcException catch (e) {
      if (e.kind == PcFailure.unreachable) {
        final found = await discoverPc(q.fingerprint, timeout: const Duration(seconds: 4));
        if (found != null && (found.host != q.host || found.port != q.port)) {
          final dio = buildDio(host: found.host, port: found.port, fingerprint: q.fingerprint);
          final r = _check(await _call(() => dio.post('/pair', data: {'secret': q.secret, 'deviceName': deviceName})));
          final d = r.data as Map;
          return (token: d['token'] as String, pcName: d['pcName'] as String, host: found.host, port: found.port);
        }
      }
      rethrow;
    }
  }

  /// Returns the PC's name. Throws [PcException] on failure.
  Future<String> ping() async {
    final r = _check(await _call(() => _dio.get('/ping')));
    return (r.data as Map)['name'] as String;
  }

  Future<void> sendLink(String url, String? title) async {
    _check(await _call(() => _dio.post('/link', data: {'url': url, if (title != null && title.isNotEmpty) 'title': title})));
  }

  /// Opens the link on the PC immediately in its default browser.
  Future<void> openLinkNow(String url, String? title) async {
    _check(await _call(() => _dio.post('/link/open', data: {'url': url, if (title != null && title.isNotEmpty) 'title': title})));
  }

  Future<void> sendPresentation(PresentationAction action) async {
    final actStr = switch (action) {
      PresentationAction.next => 'next',
      PresentationAction.prev => 'prev',
      PresentationAction.start => 'start',
      PresentationAction.exit => 'exit',
    };
    _check(await _call(() => _dio.post('/control/presentation', data: {'action': actStr})));
  }

  Future<void> sendMedia(MediaAction action) async {
    final actStr = switch (action) {
      MediaAction.playPause => 'play_pause',
      MediaAction.next => 'next',
      MediaAction.prev => 'prev',
      MediaAction.volumeUp => 'volume_up',
      MediaAction.volumeDown => 'volume_down',
      MediaAction.mute => 'mute',
    };
    _check(await _call(() => _dio.post('/control/media', data: {'action': actStr})));
  }

  Future<void> setVolume(int volumePercent) async {
    _check(await _call(() => _dio.post('/control/media', data: {
          'action': 'set_volume',
          'volume': volumePercent.clamp(0, 100),
        })));
  }

  Future<ShutdownInfo> sendPower(PowerAction action, {int? delaySeconds}) async {
    final actStr = switch (action) {
      PowerAction.lock => 'lock',
      PowerAction.sleep => 'sleep',
      PowerAction.shutdown => 'shutdown',
      PowerAction.cancelShutdown => 'cancel_shutdown',
    };
    final data = <String, Object?>{'action': actStr};
    if (delaySeconds != null) data['delaySeconds'] = delaySeconds;
    final r = _check(await _call(() => _dio.post('/control/power', data: data)));
    final d = r.data as Map;
    return ShutdownInfo.fromJson((d['shutdown'] as Map<String, dynamic>?) ?? {});
  }

  Future<String> getClipboard() async {
    final r = _check(await _call(() => _dio.get('/control/clipboard')));
    return ((r.data as Map)['text'] as String?) ?? '';
  }

  Future<void> setClipboard(String text) async {
    _check(await _call(() => _dio.post('/control/clipboard', data: {'text': text})));
  }

  Future<PcStatus> getStatus() async {
    final r = _check(await _call(() => _dio.get('/status')));
    return PcStatus.fromJson(r.data as Map<String, dynamic>);
  }

  Future<({List<LauncherItem> launchers, List<MacroItem> macros})> getLaunchers() async {
    final r = _check(await _call(() => _dio.get('/launcher/list')));
    final d = r.data as Map<String, dynamic>;
    final lList = (d['launchers'] as List?)?.map((x) => LauncherItem.fromJson(x as Map<String, dynamic>)).toList() ?? [];
    final mList = (d['macros'] as List?)?.map((x) => MacroItem.fromJson(x as Map<String, dynamic>)).toList() ?? [];
    return (launchers: lList, macros: mList);
  }

  Future<void> runLauncher(String id) async {
    _check(await _call(() => _dio.post('/launcher/run', data: {'id': id})));
  }

  Future<void> runMacro(String id) async {
    _check(await _call(() => _dio.post('/macro/run', data: {'id': id})));
  }

  Future<List<ApprovedFolder>> getApprovedFolders() async {
    final r = _check(await _call(() => _dio.get('/browse/folders')));
    final d = r.data as Map<String, dynamic>;
    return (d['folders'] as List?)?.map((x) => ApprovedFolder.fromJson(x as Map<String, dynamic>)).toList() ?? [];
  }

  Future<({String folderName, String currentPath, List<RemoteFileEntry> entries})> browseDir(
    String folderId, {
    String? subpath,
  }) async {
    final r = _check(await _call(() => _dio.get('/browse/dir', queryParameters: {
      'folderId': folderId,
      if (subpath != null && subpath.isNotEmpty) 'subpath': subpath,
    })));
    final d = r.data as Map<String, dynamic>;
    final entries = (d['entries'] as List?)?.map((x) => RemoteFileEntry.fromJson(x as Map<String, dynamic>)).toList() ?? [];
    return (
      folderName: d['folderName'] as String? ?? '',
      currentPath: d['currentPath'] as String? ?? '',
      entries: entries,
    );
  }

  Future<void> downloadRemoteFile(
    String folderId,
    String subpath,
    String saveToPath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final res = await _dio.get<ResponseBody>(
      '/browse/download',
      queryParameters: {'folderId': folderId, 'subpath': subpath},
      options: Options(responseType: ResponseType.stream),
      cancelToken: cancel,
    );
    final body = res.data;
    if (body == null) throw PcException(PcFailure.rejected, 'Failed to download file');

    final total = int.tryParse(res.headers.value('content-length') ?? '') ?? -1;
    final file = File(saveToPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();

    var received = 0;
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null) onProgress(received, total);
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> upload(String path, String name, {
    required String transferId,
    bool temporary = false,
    String? relativePath,
    String? duplicateAction,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancel,
  }) async {
    final file = File(path);
    final total = await file.length();
    final init = _check(await _call(() => _dio.post('/upload/init', data: {
      'transferId': transferId,
      'name': name,
      'size': total,
      'temporary': temporary,
      if (relativePath != null) 'relativePath': relativePath,
    }, cancelToken: cancel)));
    var offset = ((init.data as Map)['offset'] as num?)?.toInt() ?? 0;
    const chunkSize = 4 * 1024 * 1024;
    while (offset < total) {
      final end = (offset + chunkSize).clamp(0, total);
      await _check(await _call(() => _dio.put(
        '/upload/$transferId/chunk',
        data: file.openRead(offset, end),
        options: Options(
          contentType: 'application/octet-stream',
          headers: {'Content-Length': end - offset, 'X-Tandem-Offset': offset},
        ),
        cancelToken: cancel,
      )));
      offset = end;
      onProgress?.call(offset, total);
    }
    _check(await _call(() => _dio.post('/upload/$transferId/complete', data: {
      if (duplicateAction != null) 'duplicateAction': duplicateAction,
    }, cancelToken: cancel)));
  }

  Future<List<Map<String, dynamic>>> getPhoneInbox() async {
    final response = _check(await _call(() => _dio.get('/phone/inbox')));
    final values = (response.data as Map)['items'] as List? ?? const [];
    return values.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> downloadPhoneInboxFile(String id, String targetPath, {
    required int offset,
    void Function(int received, int total)? onProgress,
  }) async {
    final response = await _call(() => _dio.get<ResponseBody>(
      '/phone/inbox/$id/download',
      options: Options(
        responseType: ResponseType.stream,
        headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null,
        validateStatus: (code) => code == 200 || code == 206,
      ),
    ));
    if ((response.statusCode ?? 0) != 200 && (response.statusCode ?? 0) != 206) _check(response);
    final body = response.data as ResponseBody?;
    if (body == null) throw PcException(PcFailure.rejected, 'The PC did not return the file.');
    final total = int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
    if (offset > 0 && response.statusCode != 206) {
      throw PcException(PcFailure.rejected, 'The PC could not resume this transfer.');
    }
    final file = File(targetPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
    var received = offset;
    try {
      await for (final chunk in body.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total < 0 ? total : total + offset);
      }
    } finally {
      await sink.close();
    }
  }

  Future<void> acknowledgePhoneInboxFile(String id) async {
    _check(await _call(() => _dio.delete('/phone/inbox/$id')));
  }

  Future<void> unpair() async {
    _check(await _call(() => _dio.delete('/pair')));
  }

  Future<Map<String, dynamic>> checkUpdate() async {
    final r = _check(await _call(() => _dio.get('/update/check')));
    return Map<String, dynamic>.from(r.data as Map);
  }

  Future<Map<String, dynamic>> applyUpdate() async {
    final r = _check(await _call(() => _dio.post('/update/apply')));
    return Map<String, dynamic>.from(r.data as Map);
  }
}

/// Finds the paired PC on the local network (mDNS) by matching the certificate fingerprint it advertises.
Future<({String host, int port})?> discoverPc(String fingerprint,
    {Duration timeout = const Duration(seconds: 12)}) async {
  Discovery? d1;
  Discovery? d2;
  final done = Completer<({String host, int port})?>();
  void onService(Service service, ServiceStatus status) {
    if (status != ServiceStatus.found || done.isCompleted) return;
    final raw = service.txt?['fp'];
    if (raw == null || normFp(utf8.decode(raw)) != normFp(fingerprint)) return;
    final addr = service.addresses;
    final host = (addr != null && addr.isNotEmpty) ? addr.first.address : service.host;
    final port = service.port;
    if (host != null && port != null && !done.isCompleted) done.complete((host: host, port: port));
  }

  try {
    try {
      d1 = await startDiscovery('_tandem._tcp', ipLookupType: IpLookupType.v4);
      d1.addServiceListener(onService);
    } catch (_) {}
    try {
      d2 = await startDiscovery('_phonesaves._tcp', ipLookupType: IpLookupType.v4);
      d2.addServiceListener(onService);
    } catch (_) {}
    return await done.future.timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    if (d1 != null) {
      try {
        await stopDiscovery(d1);
      } catch (_) {}
    }
    if (d2 != null) {
      try {
        await stopDiscovery(d2);
      } catch (_) {}
    }
  }
}
