import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ads/ad_service.dart';
import '../ads/discover_native_merge.dart';
import '../data/is_ilani_repository.dart';
import '../l10n/app_strings.dart';
import '../models/is_ilani.dart';
import '../theme/app_colors.dart';

/// Firebase Realtime Database `is_ilanlari` düğümünden gelen kamu personel alım
/// ilanlarını listeleyen ekran.
class KamuIlanlariScreen extends StatefulWidget {
  KamuIlanlariScreen({super.key, IsIlaniRepository? repository})
      : repository = repository ?? IsIlaniRepository();

  final IsIlaniRepository repository;

  @override
  State<KamuIlanlariScreen> createState() => _KamuIlanlariScreenState();
}

class _KamuIlanlariScreenState extends State<KamuIlanlariScreen>
    with WidgetsBindingObserver {
  StreamSubscription<List<IsIlani>>? _sub;

  /// Repository'den gelen, tarihi geçmemiş ilanların tam listesi.
  List<IsIlani> _ilanlar = const [];

  bool _loading = true;
  String? _error;

  final TextEditingController _search = TextEditingController();

  // Native reklamlar — her 5 ilandan sonra 1 adet
  List<NativeAd> _nativeAds = const [];
  bool _nativeBusy = false;
  int _nativeGen = 0;

  // Geçiş reklamı — her 3 ilan tıklamasında dönüşte
  int _linkOpenCount = 0;
  bool _pendingInterstitialOnReturn = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _sub = widget.repository.watchIlanlar().listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _ilanlar = list;
          _loading = false;
          _error = null;
        });
        _onIlanlarChanged();
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = AppStrings.ilanlarLoadError;
        });
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeNatives();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingInterstitialOnReturn) {
      _pendingInterstitialOnReturn = false;
      unawaited(AdService.instance.showInterstitialIfReady());
    }
  }

  // -------------------------------------------------------------------------
  // Native reklam yükleme
  // -------------------------------------------------------------------------

  void _onIlanlarChanged() {
    if (!AdService.adsEnabled || kIsWeb) return;
    final needed = (_ilanlar.length ~/ 5).clamp(0, 12);
    if (needed <= 0) {
      _disposeNatives();
      return;
    }
    if (_nativeAds.length >= needed && !_nativeBusy) return;
    unawaited(_loadNativeAds(needed));
  }

  void _disposeNatives() {
    _nativeGen++;
    for (final a in _nativeAds) {
      a.dispose();
    }
    _nativeAds = const [];
    _nativeBusy = false;
  }

  Future<void> _loadNativeAds(int needed) async {
    final gen = ++_nativeGen;
    if (mounted) setState(() => _nativeBusy = true);
    final loaded = await DiscoverNativeMerge.loadPool(needed);
    if (!mounted || gen != _nativeGen) {
      for (final a in loaded) {
        a.dispose();
      }
      return;
    }
    setState(() {
      _nativeAds = loaded;
      _nativeBusy = false;
    });
  }

  /// [liste] içine her 5 ilandan sonra 1 native reklam serpiştirir.
  List<Object> _mergeWithAds(List<IsIlani> liste) {
    if (!AdService.adsEnabled || kIsWeb || _nativeAds.isEmpty) {
      return List<Object>.from(liste);
    }
    const everyN = 5;
    final out = <Object>[];
    var adIdx = 0;
    for (var i = 0; i < liste.length; i++) {
      out.add(liste[i]);
      if ((i + 1) % everyN == 0 && adIdx < _nativeAds.length) {
        out.add(_nativeAds[adIdx++]);
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // Arama
  // -------------------------------------------------------------------------

  void _onSearchChanged() => setState(() {});

  /// Tarihi geçmiş ilanlar repository tarafından zaten ayıklanmıştır.
  /// Bu metot yalnızca metin aramasını uygular.
  List<IsIlani> _filtered() {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _ilanlar;
    return _ilanlar
        .where(
          (i) =>
              i.kurum.toLowerCase().contains(q) ||
              i.pozisyon.toLowerCase().contains(q),
        )
        .toList();
  }

  // -------------------------------------------------------------------------
  // Bağlantı açma
  // -------------------------------------------------------------------------

  void _shareIlan(IsIlani ilan) {
    final metin = StringBuffer()
      ..writeln('${ilan.kurum} - ${ilan.pozisyon} ilanı yayınlandı!')
      ..writeln()
      ..writeln('Son Başvuru: ${ilan.tarih}')
      ..writeln('Detaylar ve Başvuru için: ${ilan.link}')
      ..writeln()
      ..write('(RotaLink Uygulamasından gönderilmiştir)');
    Share.share(metin.toString(), subject: '${ilan.kurum} - ${ilan.pozisyon}');
  }

  Future<void> _openLink(String link) async {
    if (link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;

    // Her 3 ilan tıklamasında bir, geri dönüşte geçiş reklamı hazırla
    _linkOpenCount++;
    if (_linkOpenCount >= 3) {
      _linkOpenCount = 0;
      _pendingInterstitialOnReturn = true;
      if (AdService.adsEnabled && !kIsWeb) {
        unawaited(AdService.instance.preloadInterstitial());
      }
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.kamuIlanlarLinkError)),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.kamuIlanlarTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _IlanlarSearchBar(controller: _search),
        ),
      ),
      body: _buildListContent(context),
    );
  }

  Widget _buildListContent(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline_rounded,
        iconColor: AppColors.mapLocationPin,
        message: _error!,
      );
    }

    if (_ilanlar.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.work_off_outlined,
        iconColor: Color(0xFFB0BEC5),
        message: AppStrings.kamuIlanlarNoActive,
      );
    }

    final liste = _filtered();

    if (liste.isEmpty) {
      return const _CenteredMessage(
        icon: Icons.search_off_rounded,
        iconColor: Color(0xFFB0BEC5),
        message: AppStrings.ilanlarNoResult,
      );
    }

    final merged = _mergeWithAds(liste);

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      itemCount: merged.length,
      itemBuilder: (context, index) {
        final item = merged[index];
        if (item is NativeAd) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: 120,
                  maxHeight: 200,
                ),
                child: AdWidget(ad: item),
              ),
            ),
          );
        }
        final ilan = item as IsIlani;
        return _IlanCard(
          ilan: ilan,
          onTap: () => _openLink(ilan.link),
          onShare: () => _shareIlan(ilan),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Alt widget'lar
// ---------------------------------------------------------------------------

/// AppBar.bottom içinde gösterilen arama çubuğu — _DiscoverSearchField ile aynı stil.
class _IlanlarSearchBar extends StatelessWidget {
  const _IlanlarSearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (_, value, child) => TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.white),
          cursorColor: AppColors.white,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: AppStrings.ilanlarSearchHint,
            hintStyle: const TextStyle(color: Color(0xA6FFFFFF)),
            prefixIcon: const Icon(Icons.search, color: Color(0xD9FFFFFF)),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.clear_rounded,
                      color: Color(0xD9FFFFFF),
                      size: 18,
                    ),
                    onPressed: controller.clear,
                    tooltip: 'Temizle',
                  ),
            filled: true,
            fillColor: const Color(0x1FFFFFFF),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0x80FFFFFF)),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: Color(0x80FFFFFF)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(14)),
              borderSide: BorderSide(color: AppColors.white),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.iconColor,
    required this.message,
  });

  final IconData icon;
  final Color iconColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: iconColor),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.campaignSummaryMuted,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IlanCard extends StatelessWidget {
  const _IlanCard({
    required this.ilan,
    required this.onTap,
    required this.onShare,
  });

  final IsIlani ilan;
  final VoidCallback onTap;
  final VoidCallback onShare;

  static const _dateColor = Color(0xFFE53935);
  static const _borderColor = Color(0xFFE0F7FA);
  static const _arrowColor = Color(0xFFB0BEC5);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 12, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sol ikon
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.account_balance_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                // İçerik
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Kurum adı — kalın
                      Text(
                        ilan.kurum,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Pozisyon — normal
                      Text(
                        ilan.pozisyon,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.campaignSummaryMuted,
                          height: 1.4,
                        ),
                      ),
                      // Tarih — sağ alt
                      if (ilan.tarih.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 13,
                                color: _dateColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                ilan.tarih,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _dateColor,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Sağ: paylaş + ok işareti
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.share_outlined),
                        iconSize: 19,
                        color: AppColors.primary.withValues(alpha: 0.70),
                        tooltip: 'Paylaş',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                        onPressed: onShare,
                      ),
                      const SizedBox(height: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _arrowColor,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
