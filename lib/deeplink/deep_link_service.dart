import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:play_install_referrer/play_install_referrer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deep_link_target.dart';

/// Web (rotalink.tr) → uygulama geçişleri: App Links / Universal Links,
/// `rotalink://open/...` şeması ve Play Install Referrer (ertelenmiş link).
///
/// Hedef [pending] üzerinden ana ekrana iletilir; ekran veri yüklenince
/// [take] ile tüketir.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final ValueNotifier<DeepLinkTarget?> pending = ValueNotifier(null);

  static const _referrerDoneKey = 'deeplink_install_referrer_done_v1';

  /// Mağaza tıklaması bundan eskiyse (ör. eski kurulum, güncelleme) yönlendirme yapılmaz.
  static const _referrerMaxAge = Duration(days: 2);

  StreamSubscription<Uri>? _sub;
  bool _started = false;
  bool _openedFromLink = false;

  /// Bu oturumda web linkiyle içerik açıldı mı (onboarding'i ertelemek için).
  bool get openedFromLink => _openedFromLink;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final appLinks = AppLinks();
    Uri? initial;
    try {
      initial = await appLinks.getInitialLink();
    } catch (e) {
      debugPrint('DeepLink initial: $e');
    }
    if (initial != null) _handle(initial);
    _sub = appLinks.uriLinkStream.listen(
      (uri) {
        if (uri == initial) {
          initial = null;
          return;
        }
        _handle(uri);
      },
      onError: (Object e) => debugPrint('DeepLink stream: $e'),
    );
    unawaited(_checkInstallReferrer(hasInitialLink: initial != null));
  }

  /// Bekleyen hedefi alır ve temizler.
  DeepLinkTarget? take() {
    final t = pending.value;
    pending.value = null;
    return t;
  }

  void _handle(Uri uri) {
    final target = DeepLinkTarget.fromUri(uri);
    if (target == null) return;
    final source = uri.scheme == DeepLinkTarget.appScheme ? 'web_to_app' : 'app_link';
    _log('deep_link_open', {
      'path': target.path,
      'source': source,
      'kind': target.kind.name,
    });
    if (target.kind != DeepLinkKind.home) _openedFromLink = true;
    pending.value = target;
  }

  Future<void> _checkInstallReferrer({required bool hasInitialLink}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_referrerDoneKey) ?? false) return;
      await prefs.setBool(_referrerDoneKey, true);

      final details = await PlayInstallReferrer.installReferrer;
      final raw = details.installReferrer;
      if (raw == null || raw.isEmpty) return;
      final Map<String, String> params;
      try {
        params = Uri.splitQueryString(raw);
      } catch (_) {
        return;
      }
      final utmSource = params['utm_source'] ?? '';
      if (utmSource.isEmpty) return;

      final rlPath = params['rl_path'];
      _log('app_install_source', {
        'utm_source': utmSource,
        'utm_medium': params['utm_medium'] ?? '',
        'utm_campaign': params['utm_campaign'] ?? '',
        'path': rlPath ?? '',
      });

      if (hasInitialLink || rlPath == null || !rlPath.startsWith('/')) return;
      final clickedAt = details.referrerClickTimestampSeconds;
      if (clickedAt > 0) {
        final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(clickedAt * 1000),
        );
        if (age > _referrerMaxAge) return;
      }
      final target = DeepLinkTarget.fromPath(rlPath);
      if (target.kind == DeepLinkKind.home) return;
      _log('deep_link_open', {
        'path': target.path,
        'source': 'install_referrer',
        'kind': target.kind.name,
      });
      _openedFromLink = true;
      pending.value ??= target;
    } catch (e) {
      debugPrint('Install referrer: $e');
    }
  }

  void _log(String name, Map<String, Object> params) {
    final clean = params.map(
      (k, v) => MapEntry(k, v is String && v.length > 100 ? v.substring(0, 100) : v),
    );
    try {
      unawaited(
        FirebaseAnalytics.instance
            .logEvent(name: name, parameters: clean)
            .catchError((Object e) => debugPrint('Analytics $name: $e')),
      );
    } catch (e) {
      debugPrint('Analytics $name: $e');
    }
  }

  @visibleForTesting
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
