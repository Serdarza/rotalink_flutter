import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../services/map_tile_cache_service.dart';

class RotalinkTileLayer extends StatelessWidget {
  const RotalinkTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.serdarza.rotalink',
      tileProvider: RotalinkCachedTileProvider.instance,
      tileDisplay: const TileDisplay.fadeIn(
        duration: Duration(milliseconds: 160),
      ),
      tileBuilder: (context, tileWidget, tile) {
        if (tile.loadError) {
          return Container(
            color: const Color(0xFFE8F0F2),
            alignment: Alignment.center,
            child: Icon(
              MapTileCacheService.instance.isOnline
                  ? Icons.map_outlined
                  : Icons.cloud_off_rounded,
              color: const Color(0xFF7CB7BF),
              size: 16,
            ),
          );
        }

        if (!tile.readyToDisplay) {
          return const ColoredBox(color: Color(0xFFF4F7F8));
        }

        return AnimatedOpacity(
          opacity: tile.readyToDisplay ? 1 : 0,
          duration: const Duration(milliseconds: 140),
          child: tileWidget,
        );
      },
    );
  }
}

/// Tek örnek — bellek önbelleği harita yeniden çizilse de korunur.
class RotalinkCachedTileProvider extends TileProvider {
  RotalinkCachedTileProvider._();

  static final RotalinkCachedTileProvider instance =
      RotalinkCachedTileProvider._();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    return _CachedTileImageProvider(url);
  }
}

class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  const _CachedTileImageProvider(this.url);

  final String url;

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_CachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(decode),
      scale: 1.0,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty('Url', url),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final bytes = await MapTileCacheService.instance.loadTile(url);
    if (bytes != null) {
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    }
    throw StateError('Tile not cached and network unavailable: $url');
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    return other is _CachedTileImageProvider && other.url == url;
  }

  @override
  int get hashCode => url.hashCode;
}
