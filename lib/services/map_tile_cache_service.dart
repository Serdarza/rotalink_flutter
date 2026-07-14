import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_service.dart';

/// OpenStreetMap karolarını bellek + disk önbelleğinde tutar.
/// İnternet varken indirir; çevrimdışıyken yalnızca önbellekten okur (ağ denemez).
class MapTileCacheService {
  MapTileCacheService._();

  static final MapTileCacheService instance = MapTileCacheService._();

  static const _memoryMaxEntries = 500;
  static const _networkTimeout = Duration(seconds: 6);
  static const _legacyPrefsPrefix = 'tile_cache_';

  Directory? _cacheDir;
  final LinkedHashMap<String, Uint8List> _memory = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _inflight = {};
  StreamSubscription<bool>? _connectivitySub;
  bool _online = true;
  bool _initialized = false;

  bool get isOnline => _online;

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    final base = await getApplicationCacheDirectory();
    _cacheDir = Directory('${base.path}/osm_tiles');
    await _cacheDir!.create(recursive: true);

    _online = await NetworkService.instance.isConnected();
    _connectivitySub ??=
        NetworkService.instance.onConnectivityChanged.listen((connected) {
      _online = connected;
    });

    _initialized = true;
    unawaited(_purgeLegacySharedPreferencesTiles());
  }

  /// Eski SharedPreferences tabanlı karo önbelleğini temizler (yavaş ve sınırlıydı).
  Future<void> _purgeLegacySharedPreferencesTiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyKeys =
          prefs.getKeys().where((k) => k.startsWith(_legacyPrefsPrefix));
      for (final key in legacyKeys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  Future<Uint8List?> loadTile(String url) {
    return _inflight.putIfAbsent(url, () async {
      try {
        await ensureInitialized();
        return _loadTileInternal(url);
      } finally {
        _inflight.remove(url);
      }
    });
  }

  Future<Uint8List?> _loadTileInternal(String url) async {
    final fromMemory = _readMemory(url);
    if (fromMemory != null) return fromMemory;

    final fromDisk = await _readDisk(url);
    if (fromDisk != null) {
      _writeMemory(url, fromDisk);
      return fromDisk;
    }

    if (!_online) return null;

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(_networkTimeout, onTimeout: () => http.Response('', 408));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final bytes = Uint8List.fromList(response.bodyBytes);
        _writeMemory(url, bytes);
        unawaited(_writeDisk(url, bytes));
        return bytes;
      }
    } catch (_) {}

    return null;
  }

  Uint8List? _readMemory(String url) {
    final bytes = _memory.remove(url);
    if (bytes == null) return null;
    _memory[url] = bytes;
    return bytes;
  }

  void _writeMemory(String url, Uint8List bytes) {
    _memory.remove(url);
    _memory[url] = bytes;
    while (_memory.length > _memoryMaxEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  Future<Uint8List?> _readDisk(String url) async {
    final dir = _cacheDir;
    if (dir == null) return null;
    final file = File(_diskPath(dir.path, url));
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String url, Uint8List bytes) async {
    final dir = _cacheDir;
    if (dir == null) return;
    try {
      final file = File(_diskPath(dir.path, url));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }

  String _diskPath(String root, String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    if (segments.length >= 3) {
      final z = segments[segments.length - 3];
      final x = segments[segments.length - 2];
      final y = segments[segments.length - 1];
      return '$root/$z/$x/$y';
    }
    final safeName = url.hashCode.toUnsigned(32).toRadixString(16);
    return '$root/misc/$safeName.tile';
  }

  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }
}
