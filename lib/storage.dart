import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// The pairing (including the access token) lives in the platform's secure storage.
class PairingStore {
  static const _key = 'pairing';
  static const _allKey = 'pairings';
  static const _selectedKey = 'selected_pairing_fingerprint';
  final _s = const FlutterSecureStorage();

  Future<Pairing?> load() async {
    final all = await loadAll();
    if (all.isEmpty) return null;
    final selected = await _s.read(key: _selectedKey);
    for (final pairing in all) {
      if (_sameFingerprint(pairing.fingerprint, selected)) return pairing;
    }
    return all.first;
  }

  Future<List<Pairing>> loadAll() async {
    final raw = await _s.read(key: _allKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        return decoded
            .map((value) => Pairing.fromJson(value as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // Recover an older single-pairing install below.
      }
    }

    final legacy = await _s.read(key: _key);
    if (legacy == null) return [];
    try {
      final pairing = Pairing.fromJson(
        jsonDecode(legacy) as Map<String, dynamic>,
      );
      await _writeAll([pairing]);
      await _s.write(key: _selectedKey, value: pairing.fingerprint);
      return [pairing];
    } catch (_) {
      return [];
    }
  }

  Future<void> save(Pairing pairing) async {
    final all = await loadAll();
    final index = all.indexWhere(
      (item) => _sameFingerprint(item.fingerprint, pairing.fingerprint),
    );
    if (index < 0) {
      all.add(pairing);
    } else {
      all[index] = pairing;
    }
    await _writeAll(all);
    await select(pairing);
  }

  Future<void> updateEndpoint(Pairing pairing) async {
    final all = await loadAll();
    final index = all.indexWhere(
      (item) => _sameFingerprint(item.fingerprint, pairing.fingerprint),
    );
    if (index < 0) return;
    all[index] = pairing;
    await _writeAll(all);
  }

  Future<void> select(Pairing pairing) =>
      _s.write(key: _selectedKey, value: pairing.fingerprint);

  Future<void> remove(Pairing pairing) async {
    final all = await loadAll();
    all.removeWhere(
      (item) => _sameFingerprint(item.fingerprint, pairing.fingerprint),
    );
    await _writeAll(all);
    final selected = await _s.read(key: _selectedKey);
    if (_sameFingerprint(selected, pairing.fingerprint)) {
      if (all.isEmpty) {
        await _s.delete(key: _selectedKey);
      } else {
        await _s.write(key: _selectedKey, value: all.first.fingerprint);
      }
    }
    await _s.delete(key: _key);
  }

  Future<void> _writeAll(List<Pairing> pairings) => _s.write(
    key: _allKey,
    value: jsonEncode(pairings.map((pairing) => pairing.toJson()).toList()),
  );

  bool _sameFingerprint(String? a, String? b) =>
      a != null &&
      b != null &&
      a.replaceAll(':', '').toLowerCase() ==
          b.replaceAll(':', '').toLowerCase();

  // Legacy compatibility for callers that only need the active connection.
  Future<void> clear() async {
    await _s.delete(key: _allKey);
    await _s.delete(key: _selectedKey);
    await _s.delete(key: _key);
  }
}

class Settings {
  Settings({this.backgroundSend = true, this.closeAfterShare = true});

  /// Retry the queue periodically in the background (Android WorkManager).
  bool backgroundSend;

  /// After sharing from another app, return to it once the item is sent or queued.
  bool closeAfterShare;

  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    return Settings(
      backgroundSend: p.getBool('backgroundSend') ?? true,
      closeAfterShare: p.getBool('closeAfterShare') ?? true,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('backgroundSend', backgroundSend);
    await p.setBool('closeAfterShare', closeAfterShare);
  }
}
