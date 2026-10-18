import 'package:flutter/material.dart';

import '../services/view_counter_service.dart';
import '../theme/ara_ui.dart';

/// Detay açıldığında görüntülenmeyi bir kez kaydeder; görünümü değiştirmez.
class ViewRecorder extends StatefulWidget {
  const ViewRecorder({super.key, required this.viewId, required this.child});

  final String viewId;
  final Widget child;

  @override
  State<ViewRecorder> createState() => _ViewRecorderState();
}

class _ViewRecorderState extends State<ViewRecorder> {
  @override
  void initState() {
    super.initState();
    ViewCounterService.instance.recordView(widget.viewId);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Kart içi küçük "👁 1.248 kişi inceledi" satırı. Sayı 0 ise hiçbir şey çizmez.
class ViewCountLabel extends StatefulWidget {
  const ViewCountLabel({super.key, required this.viewId, this.topPadding = 6});

  final String viewId;
  final double topPadding;

  @override
  State<ViewCountLabel> createState() => _ViewCountLabelState();
}

class _ViewCountLabelState extends State<ViewCountLabel> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    ViewCounterService.instance.changes.addListener(_refresh);
    _load();
  }

  @override
  void didUpdateWidget(ViewCountLabel old) {
    super.didUpdateWidget(old);
    if (old.viewId != widget.viewId) {
      _count = 0;
      _load();
    }
  }

  @override
  void dispose() {
    ViewCounterService.instance.changes.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => _load();

  Future<void> _load() async {
    final id = widget.viewId;
    final value = await ViewCounterService.instance.countFor(id);
    if (!mounted || id != widget.viewId || value == _count) return;
    setState(() => _count = value);
  }

  @override
  Widget build(BuildContext context) {
    if (_count < 1) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.topPadding),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 14,
            color: AraUi.subtleTextOf(context),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '${ViewCounterService.formatTr(_count)} kişi inceledi',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AraUi.mutedTextOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
