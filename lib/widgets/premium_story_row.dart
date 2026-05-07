import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../data/campaign_repository.dart';
import '../data/firebase_rota_repository.dart';
import '../models/campaign.dart';
import '../models/gezi_yemek_item.dart';
import '../models/misafirhane.dart';
import '../screens/campaign_detail_screen.dart';
import '../screens/discover_screen.dart';

// ---------------------------------------------------------------------------
// Veri modelleri
// ---------------------------------------------------------------------------

class _Slide {
  const _Slide({
    required this.headline,
    required this.body,
    this.badge,
    this.city,
  });
  final String headline;
  final String body;
  final String? badge;
  final String? city;
}

typedef _CtaBuilder = VoidCallback? Function(BuildContext ctx, int slideIdx);
typedef StoryNavCallback = void Function({
  required String city,
  required int tabIndex,
  required String itemName,
});

class _StoryDef {
  _StoryDef({
    required this.label,
    required this.icon,
    required this.bgColors,
    required this.ringColors,
    required this.slides,
    this.ctaLabel,
    this.ctaBuilder,
  });
  final String label;
  final IconData icon;
  final List<Color> bgColors;
  final List<Color> ringColors;
  final List<_Slide> slides;
  final String? ctaLabel;
  final _CtaBuilder? ctaBuilder;
}

// ---------------------------------------------------------------------------
// Fallback (Firebase yüklenene kadar gösterilir)
// ---------------------------------------------------------------------------

const _kampanyaFallback = <_Slide>[
  _Slide(
    headline: 'Kampanyalar Yükleniyor',
    body: 'Güncel kampanya ve fırsatlar için Keşfet sayfasını ziyaret edin.',
    badge: 'Keşfet',
  ),
  _Slide(
    headline: 'Özel Teklifler',
    body: 'Kamu personeline özel indirim ve kampanyalar RotaLink Keşfet\'te sizi bekliyor.',
    badge: 'Premium',
  ),
  _Slide(
    headline: 'Hergün Yeni Fırsat',
    body: 'Keşfet sekmesini ziyaret ederek tüm güncel kampanyaları görüntüle.',
    badge: 'Günlük',
  ),
];

const _geziFallback = <_Slide>[
  _Slide(headline: 'Gezi Yerleri', body: 'Türkiye\'nin doğal ve kültürel güzellikleri yükleniyor.', badge: 'Gezi'),
  _Slide(headline: 'Tarihi Yerler', body: 'Binlerce yıllık tarihe tanıklık eden antik kentler ve kaleler.', badge: 'Tarihi'),
  _Slide(headline: 'Doğal Güzellikler', body: 'Şelaleler, dağlar ve doğal parklar sizi bekliyor.', badge: 'Doğa'),
];

const _yemekFallback = <_Slide>[
  _Slide(headline: 'Yöresel Lezzetler', body: 'Her ilin eşsiz mutfak kültürü yükleniyor.', badge: 'Yemek'),
  _Slide(headline: 'Geleneksel Tatlar', body: 'Ata mutfağından bugüne taşınan özgün tarifler.', badge: 'Geleneksel'),
  _Slide(headline: 'Sokak Lezzetleri', body: 'Türkiye\'nin renkli ve lezzetli sokak yemekleri.', badge: 'Sokak'),
];

const _tesisFallback = <_Slide>[
  _Slide(headline: 'Tesisler Yükleniyor', body: 'Yakın tesisler ve misafirhaneler yükleniyor.', badge: 'Harita'),
  _Slide(headline: 'Misafirhaneler', body: 'Türkiye genelinde resmi konaklama tesisleri.', badge: 'Tesis'),
  _Slide(headline: 'Orduevi & Lojman', body: 'Kamu personeline özel tesis ve lojman bilgileri.', badge: 'Kamu'),
];

// ---------------------------------------------------------------------------
// Yardımcı fonksiyonlar
// ---------------------------------------------------------------------------

List<Campaign> _pick3Campaigns(List<Campaign> pool, int seed) {
  if (pool.isEmpty) return const [];
  final list = List<Campaign>.from(pool)..shuffle(Random(seed));
  return list.take(3).toList();
}

List<_Slide> _pick3FromGeziYemek(List<GeziYemekItem> items, int seed) {
  if (items.isEmpty) return const [];
  final list = List<GeziYemekItem>.from(items)..shuffle(Random(seed));
  return list.take(3).map((g) {
    final raw = g.aciklama.isNotEmpty ? g.aciklama : (g.adres.isNotEmpty ? g.adres : g.il);
    final body = raw.length > 130 ? '${raw.substring(0, 130)}…' : raw;
    return _Slide(
      headline: g.isim,
      body: body,
      badge: g.il.isNotEmpty ? g.il : null,
      city: g.il.isNotEmpty ? g.il : null,
    );
  }).toList();
}

List<_Slide> _pick3FromMisafirhaneler(List<Misafirhane> items, int seed) {
  if (items.isEmpty) return const [];
  final list = List<Misafirhane>.from(items)..shuffle(Random(seed));
  return list.take(3).map((m) {
    final raw = m.adres.isNotEmpty ? m.adres : (m.tip.isNotEmpty ? m.tip : m.il);
    final body = raw.length > 120 ? '${raw.substring(0, 120)}…' : raw;
    return _Slide(
      headline: m.isim,
      body: body,
      badge: m.il.isNotEmpty ? m.il : null,
      city: m.il.isNotEmpty ? m.il : null,
    );
  }).toList();
}

List<_StoryDef> _buildDefs(
  List<Campaign> campaigns,
  RotaDataState? rotaData,
  VoidCallback? onOpenDiscover,
  StoryNavCallback? onNavigateToCategory,
  int sessionSeed,
) {
  // ── Gezi ──────────────────────────────────────────────────────────────────
  final geziRaw = rotaData?.gezi ?? const <GeziYemekItem>[];
  final geziSlides = geziRaw.isNotEmpty
      ? _pick3FromGeziYemek(geziRaw, sessionSeed)
      : _geziFallback;

  VoidCallback? geziCta(BuildContext ctx, int idx) => () {
    final nav = Navigator.of(ctx);
    nav.pop();
    final slide = idx < geziSlides.length ? geziSlides[idx] : null;
    if (slide?.city != null && onNavigateToCategory != null) {
      onNavigateToCategory(city: slide!.city!, tabIndex: 1, itemName: slide.headline);
    } else if (onOpenDiscover != null) {
      onOpenDiscover();
    } else {
      nav.push<void>(MaterialPageRoute<void>(builder: (_) => DiscoverScreen()));
    }
  };

  // ── Yemek ─────────────────────────────────────────────────────────────────
  final yemekRaw = rotaData?.yemek ?? const <GeziYemekItem>[];
  final yemekSlides = yemekRaw.isNotEmpty
      ? _pick3FromGeziYemek(yemekRaw, sessionSeed + 17)
      : _yemekFallback;

  VoidCallback? yemekCta(BuildContext ctx, int idx) => () {
    final nav = Navigator.of(ctx);
    nav.pop();
    final slide = idx < yemekSlides.length ? yemekSlides[idx] : null;
    if (slide?.city != null && onNavigateToCategory != null) {
      onNavigateToCategory(city: slide!.city!, tabIndex: 2, itemName: slide.headline);
    } else if (onOpenDiscover != null) {
      onOpenDiscover();
    } else {
      nav.push<void>(MaterialPageRoute<void>(builder: (_) => DiscoverScreen()));
    }
  };

  // ── Kampanyalar ───────────────────────────────────────────────────────────
  final kampCampaigns = _pick3Campaigns(campaigns, sessionSeed);
  final kampSlides = kampCampaigns.isEmpty
      ? _kampanyaFallback
      : kampCampaigns
          .map((c) => _Slide(
                headline: c.title,
                body: c.summary.length > 130 ? '${c.summary.substring(0, 130)}…' : c.summary,
                badge: c.organization.isNotEmpty ? c.organization : null,
              ))
          .toList();

  _CtaBuilder? kampCta = kampCampaigns.isEmpty
      ? null
      : (ctx, idx) {
          if (idx >= kampCampaigns.length) return null;
          final camp = kampCampaigns[idx];
          return () => Navigator.push<void>(
                ctx,
                MaterialPageRoute<void>(
                  builder: (_) => CampaignDetailScreen(campaign: camp),
                ),
              );
        };

  // ── Tesis ─────────────────────────────────────────────────────────────────
  final tesisRaw = rotaData?.aramaIcinTumTesisler ?? const <Misafirhane>[];
  final tesisSlides = tesisRaw.isNotEmpty
      ? _pick3FromMisafirhaneler(tesisRaw, sessionSeed + 37)
      : _tesisFallback;

  VoidCallback? tesisCta(BuildContext ctx, int idx) => () {
    final nav = Navigator.of(ctx);
    nav.pop();
    final slide = idx < tesisSlides.length ? tesisSlides[idx] : null;
    if (slide?.city != null && onNavigateToCategory != null) {
      onNavigateToCategory(city: slide!.city!, tabIndex: 0, itemName: slide.headline);
    } else if (onOpenDiscover != null) {
      onOpenDiscover();
    } else {
      nav.push<void>(MaterialPageRoute<void>(builder: (_) => DiscoverScreen()));
    }
  };

  return [
    _StoryDef(
      label: 'Gezi',
      icon: Icons.landscape_rounded,
      bgColors: const [Color(0xFF1B5E20), Color(0xFF0D47A1)],
      ringColors: const [Color(0xFF43A047), Color(0xFF1976D2)],
      slides: geziSlides,
      ctaLabel: geziRaw.isNotEmpty ? 'İncele' : null,
      ctaBuilder: geziRaw.isNotEmpty ? geziCta : null,
    ),
    _StoryDef(
      label: 'Yemek',
      icon: Icons.restaurant_rounded,
      bgColors: const [Color(0xFFBF360C), Color(0xFF880E4F)],
      ringColors: const [Color(0xFFFF7043), Color(0xFFEC407A)],
      slides: yemekSlides,
      ctaLabel: yemekRaw.isNotEmpty ? 'İncele' : null,
      ctaBuilder: yemekRaw.isNotEmpty ? yemekCta : null,
    ),
    _StoryDef(
      label: 'Kampanyalar',
      icon: Icons.card_giftcard_rounded,
      bgColors: const [Color(0xFF4A148C), Color(0xFF1A237E)],
      ringColors: const [Color(0xFFAB47BC), Color(0xFF5C6BC0)],
      slides: kampSlides,
      ctaLabel: kampCampaigns.isNotEmpty ? 'Detay Gör' : null,
      ctaBuilder: kampCta,
    ),
    _StoryDef(
      label: 'Tesis',
      icon: Icons.apartment_rounded,
      bgColors: const [Color(0xFF1A2460), Color(0xFF0D3B6E)],
      ringColors: const [Color(0xFF1565C0), Color(0xFF0288D1)],
      slides: tesisSlides,
      ctaLabel: tesisRaw.isNotEmpty ? 'İncele' : null,
      ctaBuilder: tesisRaw.isNotEmpty ? tesisCta : null,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// Story dairelerinin yatay listesini gösterir.
/// [rotaData] Firebase'den gelen Gezi/Yemek/Tesis verisi; null ise fallback içerik gösterilir.
class PremiumStoryRow extends StatefulWidget {
  const PremiumStoryRow({
    super.key,
    this.rotaData,
    this.onOpenDiscover,
    this.onNavigateToCategory,
  });

  final RotaDataState? rotaData;
  final VoidCallback? onOpenDiscover;
  final StoryNavCallback? onNavigateToCategory;

  @override
  State<PremiumStoryRow> createState() => _PremiumStoryRowState();
}

class _PremiumStoryRowState extends State<PremiumStoryRow> {
  final int _sessionSeed = Random().nextInt(999983);
  List<Campaign> _campaigns = const [];

  @override
  void initState() {
    super.initState();
    CampaignRepository()
        .watchCampaignsOrdered()
        .first
        .then(
          (list) {
            if (mounted) setState(() => _campaigns = list);
          },
          onError: (_) {},
        );
  }

  @override
  Widget build(BuildContext context) {
    final stories = _buildDefs(
      _campaigns,
      widget.rotaData,
      widget.onOpenDiscover,
      widget.onNavigateToCategory,
      _sessionSeed,
    );
    return SizedBox(
      height: 104,
      child: LayoutBuilder(
        builder: (_, constraints) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: stories
                  .map(
                    (s) => _StoryCircle(
                      story: s,
                      onTap: () => _openViewer(context, s),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, _StoryDef story) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (ctx2, a1, a2) => _StoryViewer(
          story: story,
          onOpenDiscover: widget.onOpenDiscover,
        ),
        transitionsBuilder: (ctx3, anim, a3, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Story dairesi
// ---------------------------------------------------------------------------

class _StoryCircle extends StatelessWidget {
  const _StoryCircle({required this.story, required this.onTap});

  final _StoryDef story;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Gradient halka + iç daire
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: story.ringColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: story.ringColors[0].withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(3),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(story.icon, color: story.ringColors[0], size: 30),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                story.label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Story izleyici (tam ekran)
// ---------------------------------------------------------------------------

class _StoryViewer extends StatefulWidget {
  const _StoryViewer({required this.story, this.onOpenDiscover});
  final _StoryDef story;
  final VoidCallback? onOpenDiscover;

  @override
  State<_StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<_StoryViewer>
    with SingleTickerProviderStateMixin {
  int _slide = 0;
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _advance();
      })
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _advance() {
    if (!mounted) return;
    if (_slide < widget.story.slides.length - 1) {
      setState(() => _slide++);
      _ctrl.forward(from: 0);
    } else {
      Navigator.pop(context);
    }
  }

  void _back() {
    if (!mounted) return;
    if (_slide > 0) {
      setState(() => _slide--);
      _ctrl.forward(from: 0);
    }
  }

  VoidCallback? _buildCtaTap(BuildContext ctx) {
    final story = widget.story;
    if (story.ctaBuilder != null) {
      return story.ctaBuilder!(ctx, _slide);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final slide = story.slides[_slide];
    final size = MediaQuery.sizeOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: story.bgColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Silik arka plan ikonu
              Positioned(
                right: -40,
                bottom: size.height * 0.18,
                child: Opacity(
                  opacity: 0.09,
                  child: Icon(story.icon, size: 280, color: Colors.white),
                ),
              ),

              // Dokunma navigasyonu — alt katmanda olmalı ki cam kart butonları tap alınabilsin
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _back,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _advance,
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                ],
              ),

              // Progress bar + kapat butonu
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Column(
                  children: [
                    _ProgressBars(
                      total: story.slides.length,
                      current: _slide,
                      animation: _ctrl,
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Kategori etiketi + slide içeriği (altta)
              Positioned(
                left: 16,
                right: 16,
                bottom: 36,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Başlık bandı
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(story.icon,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 5),
                              Text(
                                story.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Glassmorphism kart
                    _GlassCard(
                      slide: slide,
                      ctaLabel: widget.story.ctaLabel,
                      onCtaTap: _buildCtaTap(context),
                    ),
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// İlerleme çubukları
// ---------------------------------------------------------------------------

class _ProgressBars extends StatelessWidget {
  const _ProgressBars({
    required this.total,
    required this.current,
    required this.animation,
  });

  final int total;
  final int current;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: i < current
                  ? const LinearProgressIndicator(
                      value: 1,
                      minHeight: 3,
                      backgroundColor: Colors.white30,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    )
                  : i == current
                      ? AnimatedBuilder(
                          animation: animation,
                          builder: (ctx4, snap) => LinearProgressIndicator(
                            value: animation.value,
                            minHeight: 3,
                            backgroundColor: Colors.white30,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const LinearProgressIndicator(
                          value: 0,
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.transparent,
                          ),
                        ),
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Glassmorphism kart
// ---------------------------------------------------------------------------

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.slide, this.ctaLabel, this.onCtaTap});
  final _Slide slide;
  final String? ctaLabel;
  final VoidCallback? onCtaTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Rozet
              if (slide.badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    slide.badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Başlık
              Text(
                slide.headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),

              // Gövde metni
              Text(
                slide.body,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.87),
                  fontSize: 14,
                  height: 1.55,
                ),
              ),

              // CTA butonu
              if (ctaLabel != null && onCtaTap != null) ...[
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: onCtaTap,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      ctaLabel!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF1A2460),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
