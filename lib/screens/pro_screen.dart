import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/pro_products.dart';
import '../billing/pro_service.dart';
import '../constants/store_links.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../theme/app_colors.dart';

/// Rotalink Pro — konaklama fiyatları ve proje desteği.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  static const List<_ProBenefit> _benefits = [
    _ProBenefit(
      icon: Icons.lock_open_outlined,
      title: 'Konaklama fiyatları',
      detail: 'Fiyat bilgisi olan tesislerde ücretleri anında görürsünüz.',
    ),
    _ProBenefit(
      icon: Icons.map_outlined,
      title: 'Aynı ücretsiz deneyim',
      detail: 'Harita, arama ve tesis bilgileri herkese açık kalır.',
    ),
    _ProBenefit(
      icon: Icons.favorite_outline,
      title: 'Projeye destek',
      detail: 'Veritabanının güncel tutulmasına katkı sağlarsınız.',
    ),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Rotalink Pro')),
      body: ValueListenableBuilder<bool>(
        valueListenable: _pro.isPro,
        builder: (context, isPro, _) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 28 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(isPro: isPro),
                const SizedBox(height: 24),
                for (final benefit in _benefits) ...[
                  _BenefitRow(benefit: benefit),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 10),
                if (isPro)
                  _ActiveCard(
                    pro: _pro,
                    onManage: _openManageSubscription,
                  )
                else
                  _PlanSection(pro: _pro),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _restoring ? null : _onRestore,
                  child: Text(
                    _restoring
                        ? 'Kontrol ediliyor…'
                        : 'Satın alımlarımı geri yükle',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Abonelik seçtiğiniz dönem sonunda otomatik yenilenir. '
                  'Yenilemeyi dilediğiniz zaman ${ProProducts.storeName} hesap '
                  'ayarlarınızdan iptal edebilirsiniz. İptal, dönem sonuna kadar '
                  'erişiminizi etkilemez.',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 12),
                const _LegalLinks(),
              ],
            ),
          );
        },
      ),
    );
  }
}

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
            style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
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
            style: TextStyle(fontSize: 12, decoration: TextDecoration.underline),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF00566B)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPro ? 'Pro etkin' : 'Rotalink Pro',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isPro
                      ? 'Desteğiniz için teşekkürler.'
                      : 'Konaklama fiyatlarını açın',
                  style: const TextStyle(
                    color: Color(0xFFB0E8EE),
                    fontSize: 13,
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

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({required this.benefit});

  final _ProBenefit benefit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(benefit.icon, size: 22, color: AppColors.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                benefit.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                benefit.detail,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.62)
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({required this.pro});

  final ProService pro;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ProductDetails>>(
      valueListenable: pro.products,
      builder: (context, products, _) {
        if (products.isEmpty) {
          return const _PlansUnavailable();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: pro.purchasePending,
          builder: (context, pending, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final product in products) ...[
                  _PlanCard(
                    product: product,
                    highlighted: product.id == ProProducts.yearly,
                    disabled: pending,
                    onTap: () => unawaited(pro.buy(product)),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.highlighted,
    required this.disabled,
    required this.onTap,
  });

  final ProductDetails product;
  final bool highlighted;
  final bool disabled;
  final VoidCallback onTap;

  String get _periodLabel =>
      product.id == ProProducts.yearly ? 'yıllık' : 'aylık';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = highlighted
        ? AppColors.primary
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.primary.withValues(alpha: 0.18));

    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Material(
        color: highlighted
            ? AppColors.primary.withValues(alpha: isDark ? 0.16 : 0.07)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: disabled ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(
                color: border,
                width: highlighted ? 1.6 : 1,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            product.id == ProProducts.yearly
                                ? 'Yıllık'
                                : 'Aylık',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (highlighted) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'En avantajlı',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${product.price} / $_periodLabel',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.68)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.primary),
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
  const _ActiveCard({
    required this.pro,
    required this.onManage,
  });

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
    final next = end == null
        ? Duration.zero
        : end.difference(DateTime.now());
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
              color: isDark
                  ? const Color(0xFF2F6B4F)
                  : const Color(0xFF9AD5B4),
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
              color: isDark
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFF14532D),
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
