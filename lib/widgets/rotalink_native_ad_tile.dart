import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Android ve iOS’ta aynı native reklam görünümü / bağlama kuralı.
///
/// [scrollingListenable] verilirse kaydırma bitene kadar placeholder gösterilir
/// (Platform View crash önlemi — her iki platformda aynı).
class RotalinkNativeAdTile extends StatefulWidget {
  const RotalinkNativeAdTile({
    super.key,
    required this.ad,
    this.scrollingListenable,
    this.height = AdNativeLayout.height,
  });

  final NativeAd ad;
  final ValueListenable<bool>? scrollingListenable;
  final double height;

  @override
  State<RotalinkNativeAdTile> createState() => _RotalinkNativeAdTileState();
}

class _RotalinkNativeAdTileState extends State<RotalinkNativeAdTile>
    with AutomaticKeepAliveClientMixin {
  bool _adAttached = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.scrollingListenable?.addListener(_onScrollingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAttach());
  }

  @override
  void didUpdateWidget(covariant RotalinkNativeAdTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollingListenable != widget.scrollingListenable) {
      oldWidget.scrollingListenable?.removeListener(_onScrollingChanged);
      widget.scrollingListenable?.addListener(_onScrollingChanged);
    }
  }

  @override
  void dispose() {
    widget.scrollingListenable?.removeListener(_onScrollingChanged);
    super.dispose();
  }

  void _onScrollingChanged() => _tryAttach();

  void _tryAttach() {
    if (!mounted || _adAttached) return;
    final scrolling = widget.scrollingListenable?.value ?? false;
    if (scrolling) return;
    setState(() => _adAttached = true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: AdNativeLayout.padding,
      child: Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(AdNativeLayout.radius),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: _adAttached
              ? AdWidget(ad: widget.ad)
              : const ColoredBox(
                  color: Color(0xFFF3F4F6),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Keşfet / misafirhane / detay — tek native layout (Android = iOS).
abstract final class AdNativeLayout {
  static const double height = 320;
  static const double radius = 16;
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);
}
