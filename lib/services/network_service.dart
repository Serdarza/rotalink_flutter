import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// İnternet bağlantısını izleyen servis.
///
/// Tüm oturum boyunca tek örnek ([instance]) üzerinden erişilir.
/// [connectivity_plus] paketinin [ConnectivityResult] akışını
/// basit bir `bool` akışına dönüştürür.
class NetworkService {
  NetworkService._();
  static final NetworkService instance = NetworkService._();

  final _connectivity = Connectivity();

  // ─── Yardımcı ──────────────────────────────────────────────────────────────

  static bool _hasConnection(List<ConnectivityResult> results) =>
      results.isNotEmpty &&
      results.any((r) => r != ConnectivityResult.none);

  // ─── API ───────────────────────────────────────────────────────────────────

  /// Şu anki bağlantı durumunu tek seferlik kontrol eder.
  Future<bool> isConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _hasConnection(results);
    } catch (_) {
      return false;
    }
  }

  /// Bağlantı durumu değiştiğinde `true` (bağlı) / `false` (bağlantı yok) yayar.
  Stream<bool> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map(_hasConnection);
}
