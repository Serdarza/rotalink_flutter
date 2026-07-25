import 'dart:io';

import 'package:flutter/material.dart';

import '../services/network_service.dart';
import '../services/rotalink_image_cache.dart';
import '../theme/app_colors.dart';

/// Ağ görselleri — disk + bellek önbelleği.
///
/// Çevrimiçi: indirir ve diske yazar.
/// Çevrimdışı: daha önce bakılan görselleri diskten gösterir (ağ denemez).
class RotalinkCachedImage extends StatefulWidget {
  const RotalinkCachedImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String url;
  final BoxFit fit;
  final IconData placeholderIcon;

  @override
  State<RotalinkCachedImage> createState() => _RotalinkCachedImageState();
}

class _RotalinkCachedImageState extends State<RotalinkCachedImage> {
  File? _file;
  bool _failed = false;
  int _gen = 0;

  static bool _isHttpUrl(String value) {
    final u = value.trim();
    return u.startsWith('https://') || u.startsWith('http://');
  }

  String get _resolved => RotalinkImageCache.normalizeUrl(widget.url.trim());

  String get _cacheKey => 'v4|$_resolved';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RotalinkCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url.trim() != widget.url.trim()) {
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final trimmed = widget.url.trim();
    if (!_isHttpUrl(trimmed)) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _file = null;
        _failed = true;
      });
      return;
    }

    if (!mounted || gen != _gen) return;
    setState(() {
      _file = null;
      _failed = false;
    });

    final key = _cacheKey;
    final resolved = _resolved;
    final headers = RotalinkImageCache.headersForUrl(resolved);

    // 1) Diskte varsa önce onu göster (çevrimdışı kritik yol).
    try {
      final cached = await RotalinkImageCache.manager.getFileFromCache(key);
      final file = cached?.file;
      if (file != null && await file.exists()) {
        if (!mounted || gen != _gen) return;
        setState(() {
          _file = file;
          _failed = false;
        });
      }
    } catch (e) {
      debugPrint('RotalinkCachedImage cache okuma: $e');
    }

    final online = await NetworkService.instance.isConnected();
    if (!online) {
      if (!mounted || gen != _gen) return;
      if (_file == null) {
        setState(() => _failed = true);
      }
      return;
    }

    // 2) Çevrimiçi: indir / yenile (getSingleFile diskte varsa ağsız dönebilir).
    try {
      final file = await RotalinkImageCache.manager.getSingleFile(
        resolved,
        key: key,
        headers: headers,
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _file = file;
        _failed = false;
      });
    } catch (e) {
      debugPrint('RotalinkCachedImage indirme hata: $resolved → $e');
      if (!mounted || gen != _gen) return;
      if (_file == null) {
        setState(() => _failed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file != null) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final logicalW = MediaQuery.sizeOf(context).width.clamp(320.0, 900.0);
      final memW = (logicalW * dpr).round().clamp(640, 1600);
      return Image.file(
        file,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: memW,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, err, stack) {
          debugPrint('RotalinkCachedImage dosya decode hata: $err');
          return _Fallback(icon: widget.placeholderIcon);
        },
      );
    }

    if (_failed) {
      return _Fallback(icon: widget.placeholderIcon);
    }

    return const _Loading();
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.primary.withValues(alpha: 0.12),
      child: Center(
        child: Icon(icon, color: AppColors.primary, size: 40),
      ),
    );
  }
}
