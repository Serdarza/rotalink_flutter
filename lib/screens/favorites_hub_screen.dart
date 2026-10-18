import 'package:flutter/material.dart';

import '../data/favorites_repository.dart';
import '../models/misafirhane.dart';
import '../theme/app_colors.dart';
import '../theme/ara_ui.dart';
import '../theme/system_ui.dart';

/// Kaydedilen tesisler için görselsiz, metin ve ikon odaklı giriş ekranı.
class FavoritesHubScreen extends StatefulWidget {
  const FavoritesHubScreen({
    super.key,
    required this.onBack,
    required this.onOpenMap,
    required this.onExplore,
  });

  final VoidCallback onBack;
  final VoidCallback onOpenMap;
  final VoidCallback onExplore;

  @override
  State<FavoritesHubScreen> createState() => _FavoritesHubScreenState();
}

class _FavoritesHubScreenState extends State<FavoritesHubScreen> {
  final _repository = FavoritesRepository();
  late Future<List<Misafirhane>> _favorites;

  @override
  void initState() {
    super.initState();
    _favorites = _repository.load();
  }

  Future<void> _remove(Misafirhane facility) async {
    final updated = await _repository.toggle(facility);
    if (!mounted) return;
    setState(() => _favorites = Future.value(updated));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${facility.isim} favorilerden çıkarıldı.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion(
      value: RotalinkSystemUi.forBrightness(Theme.of(context).brightness),
      child: Material(
        color: AraUi.pageOf(context),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(onBack: widget.onBack),
              Expanded(
                child: FutureBuilder<List<Misafirhane>>(
                  future: _favorites,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }
                    final favorites = snapshot.data ?? const [];
                    if (favorites.isEmpty) {
                      return _EmptyState(onExplore: widget.onExplore);
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      children: [
                        Text(
                          '${favorites.length}/${FavoritesRepository.maxFavorites} '
                          'tesis kaydedildi',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        for (final facility in favorites.reversed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _FavoriteCard(
                              facility: facility,
                              onTap: widget.onOpenMap,
                              onRemove: () => _remove(facility),
                            ),
                          ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: widget.onOpenMap,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Tümünü haritada göster'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Ana sayfaya dön',
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Favorilerim',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: AppColors.primary,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.facility,
    required this.onTap,
    required this.onRemove,
  });

  final Misafirhane facility;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  IconData get _icon {
    final type = facility.tip.toLowerCase();
    if (type.contains('ordu')) return Icons.shield_outlined;
    if (type.contains('polis')) return Icons.local_police_outlined;
    if (type.contains('öğret') || type.contains('ogret')) {
      return Icons.school_outlined;
    }
    return Icons.bed_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final location = [
      facility.ilce.trim(),
      facility.il.trim(),
    ].where((part) => part.isNotEmpty).join(' · ');
    final type = facility.tip.trim().isEmpty
        ? 'Konaklama'
        : facility.tip.trim();

    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderOf(context)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_icon, color: AppColors.primary, size: 27),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      facility.isim.trim().isEmpty
                          ? 'Tesis'
                          : facility.isim.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        type,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(
                  Icons.favorite_rounded,
                  color: AppColors.primary,
                ),
                tooltip: 'Favoriden çıkar',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Henüz favoriniz yok',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Beğendiğiniz tesisleri kaydedin; daha sonra burada ve haritada '
              'kolayca bulun.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textMutedOf(context)),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: onExplore,
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Tesisleri keşfet'),
            ),
          ],
        ),
      ),
    );
  }
}
