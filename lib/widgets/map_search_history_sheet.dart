import 'package:flutter/material.dart';

import '../services/location_discovery_query.dart';
import '../services/map_search_history.dart';
import '../theme/app_colors.dart';

/// Harita arama kutusunun telefondaki geçmişi. Sunucuya gitmez.
Future<void> showMapSearchHistorySheet({
  required BuildContext context,
  required Future<void> Function(MapHistoryEntry entry) onReplay,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surfaceOf(context),
    builder: (sheetContext) => _MapSearchHistorySheet(onReplay: onReplay),
  );
}

class _MapSearchHistorySheet extends StatefulWidget {
  const _MapSearchHistorySheet({required this.onReplay});

  final Future<void> Function(MapHistoryEntry entry) onReplay;

  @override
  State<_MapSearchHistorySheet> createState() => _MapSearchHistorySheetState();
}

class _MapSearchHistorySheetState extends State<_MapSearchHistorySheet> {
  var _items = const <MapHistoryEntry>[];
  var _loading = true;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await LocalMapSearchHistory.load();
    if (!mounted) return;
    setState(() {
      _items = saved;
      _loading = false;
    });
  }

  Future<void> _replay(MapHistoryEntry entry) async {
    setState(() => _busyId = entry.id);
    try {
      await widget.onReplay(entry);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(MapHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kaydı sil'),
        content: Text('${entry.displayName} geçmişten kaldırılsın mı?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyId = entry.id);
    await LocalMapSearchHistory.delete(entry.id);
    if (!mounted) return;
    setState(() {
      _items = [
        for (final item in _items)
          if (item.id != entry.id) item,
      ];
      _busyId = null;
    });
  }

  String _when(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.day)}.${two(time.month)}.${time.year} ${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Geçmiş',
                style: TextStyle(
                  color: AppColors.textStrongOf(context),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(child: _body(context)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return _note(context, 'Henüz harita araması yok.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _card(context, _items[index]),
    );
  }

  Widget _note(BuildContext context, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMutedOf(context)),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, MapHistoryEntry entry) {
    final busy = _busyId == entry.id;
    return Material(
      color: AppColors.canvasOf(context),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textStrongOf(context),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.addressSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textMutedOf(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${LocationDiscoveryQuery.radiusLabel(entry.radiusKm)} · ${entry.facilityType} · ${entry.resultCount} tesis',
              style: TextStyle(
                color: AppColors.textMutedOf(context),
                fontSize: 12,
              ),
            ),
            Text(
              _when(entry.searchedAt),
              style: TextStyle(
                color: AppColors.textMutedOf(context),
                fontSize: 12,
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: busy ? null : () => _replay(entry),
                  child: const Text('Tekrar gör'),
                ),
                TextButton(
                  onPressed: busy ? null : () => _delete(entry),
                  child: const Text('Sil'),
                ),
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
