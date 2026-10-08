import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/pro_gift_code.dart';
import '../billing/pro_products.dart';
import '../billing/pro_service.dart';
import '../constants/store_links.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../theme/app_colors.dart';

/// Rotalink Pro — ücretli özellikler ve uygulamanın geliştirilmesine destek.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  static const List<_ProBenefit> _benefits = [
    _ProBenefit(
      icon: Icons.payments_outlined,
      title: 'Konaklama fiyatları',
      detail:
          'Fiyat bilgisi olan misafirhane ve tesislerde güncel ücretleri '
          'anında görün.',
    ),
    _ProBenefit(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Fiyat sıralaması ve bütçe filtresi',
      detail:
          'Tesisleri ucuzdan pahalıya dizin, bütçenizi aşanları tek '
          'dokunuşla gizleyin.',
    ),
    _ProBenefit(
      icon: Icons.calculate_outlined,
      title: 'Konaklama ücreti hesaplama',
      detail:
          'Gece, yetişkin, çocuk, ek yatak ve kahvaltıya göre toplam '
          'konaklama ücretini tarifeden hesaplayın.',
    ),
    _ProBenefit(
      icon: Icons.compare_arrows_rounded,
      title: 'Tesis karşılaştırma',
      detail:
          '3 tesise kadar fiyat, uzaklık ve konaklama şartlarını yan yana '
          'görün.',
    ),
    _ProBenefit(
      icon: Icons.notifications_active_outlined,
      title: 'Fiyat ve kampanya bildirimleri',
      detail:
          'Favori tesisinizin fiyatı değişince ve mesleğinize yeni kampanya '
          'gelince haber alın.',
    ),
  ];

  static const List<String> _freeFeatures = [
    'Harita ve arama',
    'Tesis bilgileri',
    'Kamu kampanyaları',
    'Resmî tatiller',
    '3 tesisin fiyatı',
  ];

  final ProService _pro = ProService.instance;
  StreamSubscription<String>? _messageSub;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _messageSub = _pro.messages.listen(_showMessage);
    // Ekran açılışında plan listesi boşsa mağazadan tekrar dene.
    if (_pro.products.value.isEmpty) {
      unawaited(_pro.loadProducts());
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _onRestore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    await _pro.restore();
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _openManageSubscription() async {
    final uri = Uri.parse(ProProducts.manageUrl(_pro.activeProductId));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showMessage('Abonelik sayfası açılamadı.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = RotalinkShellScope.scrollBottomPadding(context);
    final muted = _mutedText(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Rotalink Pro')),
      body: ValueListenableBuilder<bool>(
        valueListenable: _pro.isPro,
        builder: (context, isPro, _) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 28 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(isPro: isPro || _pro.giftActive),
                const SizedBox(height: 14),
                _SupportCard(isPro: isPro || _pro.giftActive),
                const SizedBox(height: 26),
                const _SectionTitle('Pro ile gelenler'),
                const SizedBox(height: 12),
                for (final benefit in _benefits) ...[
                  _BenefitTile(benefit: benefit),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 4),
                const _FreeFeatures(items: _freeFeatures),
                const SizedBox(height: 26),
                if (isPro)
                  _ActiveCard(pro: _pro, onManage: _openManageSubscription)
                else ...[
                  const _SectionTitle('Planınızı seçin'),
                  const SizedBox(height: 12),
                  _PlanSection(pro: _pro),
                  const SizedBox(height: 18),
                  _GiftCodeCard(pro: _pro),
                ],
                const SizedBox(height: 14),
                TextButton(
                  onPressed: _restoring ? null : _onRestore,
                  child: Text(
                    _restoring
                        ? 'Kontrol ediliyor…'
                        : 'Satın alımlarımı geri yükle',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Ödeme, satın alma onayıyla ${ProProducts.storeName} '
                  'hesabınızdan alınır. Abonelik, dönem bitmeden en az 24 saat '
                  'önce iptal edilmezse aynı ücretle otomatik yenilenir. '
                  'Yenilemeyi dilediğiniz zaman ${ProProducts.storeName} hesap '
                  'ayarlarınızdan kapatabilirsiniz; iptal, dönem sonuna kadar '
                  'erişiminizi etkilemez.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, height: 1.5, color: muted),
                ),
                const SizedBox(height: 10),
                const _LegalLinks(),
              ],
            ),
          );
        },
      ),
    );
  }
}

Color _mutedText(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? Colors.white.withValues(alpha: 0.62)
    : const Color(0xFF6B7280);

class _LegalLinks extends StatelessWidget {
  const _LegalLinks();

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          onPressed: () => unawaited(_open(StoreLinks.privacyPolicy)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.primary,
          ),
          child: const Text(
            'Gizlilik Politikası',
            style: TextStyle(
              fontSize: 12,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const Text(' · ', style: TextStyle(color: Color(0xFF9CA3AF))),
        TextButton(
          onPressed: () => unawaited(_open(StoreLinks.termsOfUse)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.primary,
          ),
          child: const Text(
            'Kullanım Koşulları',
            style: TextStyle(
              fontSize: 12,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF00566B)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  isPro
                      ? Icons.verified_rounded
                      : Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  isPro ? 'Pro üyesisiniz' : 'Rotalink Pro',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            isPro
                ? 'Rotalink\'i desteklediğiniz için teşekkür ederiz. Tüm Pro '
                      'özellikleri hesabınızda açık.'
                : 'Konaklamada doğru fiyatı görün, bütçenize uygun tesisi '
                      'saniyeler içinde bulun.',
            style: const TextStyle(
              color: Color(0xFFD7F3F6),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (!isPro) ...[
            const SizedBox(height: 14),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeroChip(
                  icon: Icons.event_repeat_rounded,
                  label: 'İstediğiniz zaman iptal',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reklamsız bağımsız geliştirme: aboneliğin neyi mümkün kıldığı.
class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFFFDA4AF) : const Color(0xFFE11D48);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3B1620) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF6B2536) : const Color(0xFFFECDD3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.favorite_rounded, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPro
                      ? 'Desteğiniz Rotalink\'i büyütüyor'
                      : 'Reklam yok, desteğiniz var',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFFFE4E6)
                        : const Color(0xFF881337),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isPro
                      ? 'Rotalink\'te reklam göstermiyoruz. Aboneliğiniz; tesis '
                            'bilgilerinin ve fiyatların güncel tutulmasına, yeni '
                            'özelliklerin geliştirilmesine doğrudan katkı sağlıyor.'
                      : 'Rotalink\'te reklam göstermiyoruz. Tesis bilgilerini ve '
                            'fiyatları güncel tutmak, yeni özellikler geliştirmek ve '
                            'sunucu giderlerini karşılamak Pro üyelerimizin '
                            'desteğiyle mümkün oluyor.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.75)
                        : const Color(0xFF9F1239),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.1,
      ),
    );
  }
}

class _ProBenefit {
  const _ProBenefit({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.benefit});

  final _ProBenefit benefit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(benefit.icon, size: 21, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  benefit.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  benefit.detail,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: _mutedText(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeFeatures extends StatelessWidget {
  const _FreeFeatures({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Herkes için ücretsiz kalmaya devam eder',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final item in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 15, color: muted),
                  const SizedBox(width: 4),
                  Text(item, style: TextStyle(fontSize: 12.5, color: muted)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _PlanSection extends StatefulWidget {
  const _PlanSection({required this.pro});

  final ProService pro;

  @override
  State<_PlanSection> createState() => _PlanSectionState();
}

class _PlanSectionState extends State<_PlanSection> {
  String _selectedId = ProProducts.yearly;

  static String _money(ProductDetails p, double value) {
    final floored = (value * 100).floorToDouble() / 100;
    return NumberFormat.currency(
      locale: 'tr_TR',
      symbol: p.currencySymbol,
      decimalDigits: 2,
    ).format(floored);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ProductDetails>>(
      valueListenable: widget.pro.products,
      builder: (context, products, _) {
        if (products.isEmpty) {
          return const _PlansUnavailable();
        }
        ProductDetails? byId(String id) {
          for (final p in products) {
            if (p.id == id) return p;
          }
          return null;
        }

        final monthly = byId(ProProducts.monthly);
        final yearly = byId(ProProducts.yearly);
        final ordered = [?yearly, ?monthly];
        final selected = byId(_selectedId) ?? ordered.first;

        int? savingPercent;
        if (monthly != null && yearly != null && monthly.rawPrice > 0) {
          final pct = ((1 - yearly.rawPrice / (monthly.rawPrice * 12)) * 100)
              .floor();
          if (pct >= 10) savingPercent = pct;
        }

        return ValueListenableBuilder<bool>(
          valueListenable: widget.pro.purchasePending,
          builder: (context, pending, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final product in ordered) ...[
                  _PlanOption(
                    title: product.id == ProProducts.yearly
                        ? 'Yıllık'
                        : 'Aylık',
                    price: product.price,
                    period: product.id == ProProducts.yearly ? '/ yıl' : '/ ay',
                    subtitle: product.id == ProProducts.yearly
                        ? 'Ayda ${_money(product, product.rawPrice / 12)} · 12 ay kesintisiz'
                        : 'Esnek kullanım, istediğiniz zaman iptal',
                    badge:
                        product.id == ProProducts.yearly &&
                            savingPercent != null
                        ? '%$savingPercent tasarruf'
                        : null,
                    selected: product.id == selected.id,
                    disabled: pending,
                    onTap: () => setState(() => _selectedId = product.id),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 6),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed: pending
                        ? null
                        : () => unawaited(widget.pro.buy(selected)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: pending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            selected.id == ProProducts.yearly
                                ? 'Yıllık Pro\'ya geç · ${selected.price}'
                                : 'Aylık Pro\'ya geç · ${selected.price}',
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Güvenli ödeme ${ProProducts.storeName} üzerinden yapılır.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: _mutedText(context)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({
    required this.title,
    required this.price,
    required this.period,
    required this.subtitle,
    required this.badge,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  final String title;
  final String price;
  final String period;
  final String subtitle;
  final String? badge;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = selected
        ? AppColors.primary
        : (isDark
              ? Colors.white.withValues(alpha: 0.14)
              : AppColors.primary.withValues(alpha: 0.18));

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
            decoration: BoxDecoration(
              border: Border.all(color: border, width: selected ? 2 : 1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.primary : _mutedText(context),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (badge != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: _mutedText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      period,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _mutedText(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlansUnavailable extends StatelessWidget {
  const _PlansUnavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0C36D)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xFF8A6100), size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Abonelik planları şu anda yüklenemedi. İnternet bağlantınızı '
              'kontrol edip tekrar deneyin.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Color(0xFF6B4E00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveCard extends StatefulWidget {
  const _ActiveCard({required this.pro, required this.onManage});

  final ProService pro;
  final VoidCallback onManage;

  @override
  State<_ActiveCard> createState() => _ActiveCardState();
}

class _ActiveCardState extends State<_ActiveCard> {
  Timer? _tick;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.pro.expiryAt.addListener(_onExpiryChanged);
    _syncRemaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _syncRemaining());
  }

  @override
  void dispose() {
    _tick?.cancel();
    widget.pro.expiryAt.removeListener(_onExpiryChanged);
    super.dispose();
  }

  void _onExpiryChanged() => _syncRemaining();

  void _syncRemaining() {
    final end = widget.pro.expiryAt.value;
    final next = end == null ? Duration.zero : end.difference(DateTime.now());
    final clamped = next.isNegative ? Duration.zero : next;
    if (!mounted) return;
    if (clamped != _remaining) {
      setState(() => _remaining = clamped);
    }
  }

  String get _planLabel {
    final id = widget.pro.activeProductId;
    if (id == ProProducts.yearly) return 'Yıllık plan';
    if (id == ProProducts.monthly) return 'Aylık plan';
    return 'Pro abonelik';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasCountdown = widget.pro.expiryAt.value != null;
    final days = _remaining.inDays;
    final hours = _remaining.inHours.remainder(24);
    final minutes = _remaining.inMinutes.remainder(60);
    final seconds = _remaining.inSeconds.remainder(60);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF0F3D2E), Color(0xFF14532D)]
                  : const [Color(0xFFE9F7EF), Color(0xFFD8F3E4)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF2F6B4F) : const Color(0xFF9AD5B4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    color: isDark
                        ? const Color(0xFF86EFAC)
                        : const Color(0xFF1B7A4B),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Pro aboneliğiniz aktif',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFDCFCE7)
                            : const Color(0xFF14532D),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '$_planLabel · Fiyatlar açık',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.72)
                      : const Color(0xFF166534),
                ),
              ),
              if (hasCountdown) ...[
                const SizedBox(height: 18),
                Text(
                  'Yenilemeye kalan süre',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.55)
                        : const Color(0xFF3F6B52),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _CountdownUnit(
                        value: days,
                        label: 'Gün',
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CountdownUnit(
                        value: hours,
                        label: 'Saat',
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CountdownUnit(
                        value: minutes,
                        label: 'Dk',
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CountdownUnit(
                        value: seconds,
                        label: 'Sn',
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: widget.onManage,
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: const Text('Aboneliği yönet'),
        ),
      ],
    );
  }
}

class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({
    required this.value,
    required this.label,
    required this.isDark,
  });

  final int value;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final digits = value.toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : const Color(0xFF9AD5B4).withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        children: [
          Text(
            digits,
            style: TextStyle(
              fontSize: 22,
              height: 1.1,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: isDark ? const Color(0xFFECFDF5) : const Color(0xFF14532D),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : const Color(0xFF3F6B52),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hediye Pro kodu: aktif hediye bilgisi ve kod girişi.
class _GiftCodeCard extends StatefulWidget {
  const _GiftCodeCard({required this.pro});

  final ProService pro;

  @override
  State<_GiftCodeCard> createState() => _GiftCodeCardState();
}

class _GiftCodeCardState extends State<_GiftCodeCard> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ProGiftCodes.redeem(_controller.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.ok ? null : result.message;
      if (result.ok) _controller.clear();
    });
    if (result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = _mutedText(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : AppColors.primary.withValues(alpha: 0.18),
        ),
      ),
      child: ValueListenableBuilder<DateTime?>(
        valueListenable: widget.pro.giftEndsAt,
        builder: (context, giftEnd, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (giftEnd != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF14352A)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${ProGiftCodes.planLabel(widget.pro.giftPlan)} '
                          'hediye Pro aktif\n'
                          '${ProGiftCodes.formatDate(giftEnd)} tarihine kadar',
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.4,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                children: [
                  const Icon(
                    Icons.redeem_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    giftEnd != null
                        ? 'Başka bir kodunuz mu var?'
                        : 'Hediye kodunuz mu var?',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Size verilen aylık veya yıllık Pro kodunu yazın. Yeni kod, '
                'süren hediyenizin sonuna eklenir.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: muted),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 32,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => unawaited(_redeem()),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: 'XXXX-XXXX-XXXX-XXXX',
                  counterText: '',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_redeem()),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Kodu kullan',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
