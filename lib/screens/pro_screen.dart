import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../billing/premium_presentation.dart';
import '../billing/premium_account_bridge.dart';
import '../billing/premium_auth_service.dart';
import '../billing/pro_products.dart';
import '../constants/store_links.dart';
import '../navigation/rotalink_shell_scope.dart';
import '../theme/app_colors.dart';
import '../theme/system_ui.dart';
import '../widgets/premium_usage_widgets.dart';

/// Keeps /pro navigation intact. The default adapter reads catalog and legacy
/// state; new subscriptions require the verified Stage 3 account adapter.
class ProScreen extends StatefulWidget {
  const ProScreen({super.key, this.controller, this.closeWhenPurchased = false});
  final PremiumUiController? controller;
  final bool closeWhenPurchased;
  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  late final PremiumUiController _controller;
  StreamSubscription<String>? _messages;
  StreamSubscription<User?>? _accountChanges;
  final _plansKey = GlobalKey();
  PremiumPlan _selected = PremiumPlan.gold;
  var _returnAfterPurchase = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        StorePremiumUiController(
          accountBridge: ServerPremiumAccountBridge.instance,
        );
    _messages = _controller.messages.listen(_showMessage);
    _controller.addListener(_maybeReturnToKonum);
    if (widget.controller == null) {
      _accountChanges = PremiumAuthService.instance.userChanges.listen((_) {
        unawaited(_run(_controller.refresh));
      });
    }
    unawaited(_run(_controller.refresh));
  }

  @override
  void dispose() {
    _messages?.cancel();
    _accountChanges?.cancel();
    _controller.removeListener(_maybeReturnToKonum);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on PremiumSignInCanceled {
      return;
    } on StateError catch (error) {
      _showMessage(error.message);
    } on FirebaseAuthException catch (error) {
      _showMessage(
        error.code == 'requires-recent-login'
            ? 'Hesabı silmek için yeniden giriş yapıp tekrar deneyin.'
            : 'Hesap işlemi tamamlanamadı.',
      );
    } catch (_) {
      _showMessage('İşlem tamamlanamadı. Lütfen tekrar deneyin.');
    }
  }

  Future<void> _buy(PremiumPlan plan) async {
    if (widget.closeWhenPurchased) _returnAfterPurchase = true;
    if (widget.controller == null) {
      await PremiumAuthService.instance.ensureAccountForPurchase();
      await _controller.refresh();
      if (_controller.state.account == null) {
        await _controller.refresh();
      }
    }
    await _controller.purchase(plan);
  }

  void _maybeReturnToKonum() {
    if (!widget.closeWhenPurchased || !_returnAfterPurchase || !mounted) {
      return;
    }
    final state = _controller.state;
    if (state.purchasePending || state.account?.plan == null) return;
    _returnAfterPurchase = false;
    Navigator.of(context).pop(true);
  }

  void _showPlans() {
    final target = _plansKey.currentContext;
    if (target != null) {
      unawaited(
        Scrollable.ensureVisible(
          target,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 280),
          alignment: 0.03,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: RotalinkSystemUi.forBrightness(Theme.of(context).brightness),
    child: Scaffold(
      backgroundColor: AppColors.canvasOf(context),
      appBar: AppBar(
        title: const Text('Pro'),
        backgroundColor: AppColors.canvasOf(context),
        foregroundColor: AppColors.textStrongOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final state = _controller.state;
          final account = state.account;
          return SafeArea(
            top: false,
            bottom: false,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                28 + RotalinkShellScope.scrollBottomPadding(context),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _PremiumHero(),
                      const SizedBox(height: 16),
                      if (state.legacy.hasAccess) ...[
                        _LegacyMembership(
                          legacy: state.legacy,
                          onManage: () =>
                              unawaited(_run(_controller.manageSubscription)),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (account != null) ...[
                        PremiumUsageSummary(
                          account: account,
                          onManage: state.purchasePending || state.restoring
                              ? null
                              : () => unawaited(
                                  _run(_controller.manageSubscription),
                                ),
                          onChoosePlan: _showPlans,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _SectionHeading(
                        key: _plansKey,
                        title: 'Paketinizi seçin',
                      ),
                      const SizedBox(height: 12),
                      for (final plan in const [
                        PremiumPlan.silver,
                        PremiumPlan.gold,
                        PremiumPlan.platinum,
                      ]) ...[
                        _PlanCard(
                          plan: plan,
                          selected: _selected == plan,
                          state: state,
                          onSelect: () => setState(() => _selected = plan),
                        ),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 6),
                      _StartButton(
                        plan: _selected,
                        state: state,
                        linkAccountOnBuy: widget.controller == null,
                        onBuy: () => unawaited(_run(() => _buy(_selected))),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ödeme, telefonda açık olan ${ProProducts.storeName} hesabından alınır. Ayrı oturum açılmaz. Aynı hesap sonraki telefonda da tanınır.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMutedOf(context),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                      if (state.catalogMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          state.catalogMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textMutedOf(context),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ],
                      TextButton.icon(
                        key: const ValueKey('premium-restore'),
                        onPressed: state.restoring || state.purchasePending
                            ? null
                            : () => unawaited(_run(_controller.restore)),
                        icon: const Icon(Icons.restore_rounded, size: 18),
                        label: Text(
                          state.restoring
                              ? 'Kontrol ediliyor…'
                              : 'Satın almayı geri yükle',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          for (final link in [
                            ('Gizlilik Politikası', StoreLinks.privacyPolicy),
                            ('Kullanım Koşulları', StoreLinks.termsOfUse),
                          ])
                            TextButton(
                              onPressed: () => unawaited(
                                _run(() async {
                                  if (!await launchUrl(
                                    Uri.parse(link.$2),
                                    mode: LaunchMode.externalApplication,
                                  )) {
                                    throw StateError('Link unavailable');
                                  }
                                }),
                              ),
                              child: Text(
                                link.$1,
                                style: const TextStyle(fontSize: 11.5),
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
        },
      ),
    ),
  );
}

class _PremiumHero extends StatelessWidget {
  const _PremiumHero();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0A8A98), Color(0xFF07586A), Color(0xFF123448)],
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x330A8A98),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rotalink Pro',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            height: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Reklamsız Rotalink, sizin desteğinizle büyüyor! 💚',
          style: TextStyle(
            color: Color(0xFFE7F6F8),
            fontSize: 15,
            height: 1.4,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Pro aboneliğiniz yalnızca ayrıcalıklı özelliklere erişim değil, Rotalink\'in gelişimine ve hizmetlerini sürdürebilmesine verdiğiniz değerli bir destektir.',
          style: TextStyle(color: Color(0xFFE7F6F8), fontSize: 15, height: 1.4),
        ),
      ],
    ),
  );
}

({Color accent, List<Color> colors}) _metalOf(PremiumPlan plan, bool dark) {
  return switch (plan) {
    PremiumPlan.silver => (
      accent: dark ? const Color(0xFFD5DEE6) : const Color(0xFF5E6E7E),
      colors: dark
          ? const [Color(0xFF3A4550), Color(0xFF242C33)]
          : const [Color(0xFFF7F8FA), Color(0xFFD5DEE6)],
    ),
    PremiumPlan.gold => (
      accent: dark ? const Color(0xFFF3CA6A) : const Color(0xFF8A5A10),
      colors: dark
          ? const [Color(0xFF3C3218), Color(0xFF262014)]
          : const [Color(0xFFFFF8E8), Color(0xFFFFEFC4)],
    ),
    PremiumPlan.platinum || PremiumPlan.legacyPlatinum => (
      accent: dark ? const Color(0xFFE6D4FF) : const Color(0xFF5A2D91),
      colors: dark
          ? const [Color(0xFF3A2458), Color(0xFF1C102E)]
          : const [Color(0xFFF6EEFF), Color(0xFFCDB4EE)],
    ),
  };
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.state,
    required this.onSelect,
  });
  final PremiumPlan plan;
  final bool selected;
  final PremiumUiState state;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark(context);
    final featured = plan == PremiumPlan.gold;
    final metal = _metalOf(plan, dark);
    final accent = metal.accent;
    final offer = state.offers[plan];
    final active =
        state.account?.plan == plan &&
        (state.account?.status == PremiumSubscriptionStatus.active ||
            state.account?.status == PremiumSubscriptionStatus.renewalOff);
    final loading = state.catalogPhase == PremiumCatalogPhase.loading;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(featured ? 20 : 16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.fromLTRB(
            14,
            featured ? 14 : 12,
            14,
            featured ? 14 : 12,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: metal.colors,
            ),
            borderRadius: BorderRadius.circular(featured ? 20 : 16),
            border: Border.all(
              color: featured || selected
                  ? accent
                  : AppColors.borderOf(context),
              width: featured || selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: dark ? 0.2 : 0.16),
                blurRadius: featured ? 16 : 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected ? accent : AppColors.textMutedOf(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (featured)
                      Text(
                        'ÖNERİLEN PAKET',
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    Text(
                      plan.title,
                      style: TextStyle(
                        color: AppColors.textStrongOf(context),
                        fontSize: featured ? 18 : 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      plan == PremiumPlan.gold
                          ? 'Önerilen · ${plan.pitch}'
                          : plan.pitch,
                      style: TextStyle(
                        color: accent,
                        fontSize: 12.5,
                        fontWeight: featured
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      PremiumRightsCatalog.instance.of(plan).line,
                      style: TextStyle(
                        color: AppColors.textMutedOf(context),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    if (active)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Şu anki paketiniz',
                          style: TextStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else if (offer == null &&
                        state.catalogPhase == PremiumCatalogPhase.error)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Fiyat şu anda alınamıyor',
                          style: TextStyle(fontSize: 12),
                        ),
                      )
                    else if (offer == null && loading)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Mağaza fiyatı yükleniyor…',
                          style: TextStyle(
                            color: AppColors.textMutedOf(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (offer != null) ...[
                const SizedBox(width: 8),
                Text(
                  offer.product.price,
                  style: TextStyle(
                    color: accent,
                    fontSize: featured ? 18 : 15,
                    fontWeight: FontWeight.w800,
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

class _StartButton extends StatelessWidget {
  const _StartButton({
    required this.plan,
    required this.state,
    required this.linkAccountOnBuy,
    required this.onBuy,
  });
  final PremiumPlan plan;
  final PremiumUiState state;
  final bool linkAccountOnBuy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final offer = state.offers[plan];
    final active =
        state.account?.plan == plan &&
        (state.account?.status == PremiumSubscriptionStatus.active ||
            state.account?.status == PremiumSubscriptionStatus.renewalOff);
    final linkReady =
        linkAccountOnBuy &&
        offer != null &&
        state.account == null &&
        !state.legacy.hasAccess &&
        !active;
    final canBuy =
        ((state.canPurchase(plan) && !active) || linkReady) &&
        !state.purchasePending &&
        !state.restoring;
    final current = state.account?.plan;
    final hasCurrentPlan =
        current != null &&
        (state.account?.status == PremiumSubscriptionStatus.active ||
            state.account?.status == PremiumSubscriptionStatus.renewalOff);
    final label = active
        ? 'Aktif paketiniz'
        : state.purchasePending
        ? 'İşlem sürüyor…'
        : !hasCurrentPlan
        ? 'Aboneliği başlat'
        : plan.index > current.index
        ? 'Paket yükselt'
        : 'Paketi değiştir';
    return FilledButton(
      key: ValueKey('premium-buy-${plan.name}'),
      onPressed: canBuy ? onBuy : null,
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.borderOf(context),
        disabledForegroundColor: AppColors.textMutedOf(context),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      child: Text(label),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({super.key, required this.title});
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: AppColors.textStrongOf(context),
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _LegacyMembership extends StatelessWidget {
  const _LegacyMembership({required this.legacy, required this.onManage});
  final LegacyProSnapshot legacy;
  final VoidCallback onManage;
  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('legacy-pro-membership'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surfaceOf(context),
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
      borderRadius: BorderRadius.circular(21),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.verified_outlined, color: AppColors.primary),
        const SizedBox(height: 9),
        Text(
          'Mevcut Pro üyeliğiniz',
          style: TextStyle(
            color: AppColors.textStrongOf(context),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        if (legacy.active) ...[
          Text(
            '${legacy.productId == ProProducts.yearly ? 'Yıllık Pro' : 'Aylık Pro'} · Erişiminiz devam ediyor.',
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 13,
            ),
          ),
          if (legacy.estimatedEnd != null) ...[
            const SizedBox(height: 4),
            Text(
              'Kayıtlı dönem bitişi: ${DateFormat('dd.MM.yyyy').format(legacy.estimatedEnd!.toLocal())}',
              style: TextStyle(
                color: AppColors.textMutedOf(context),
                fontSize: 12,
              ),
            ),
          ],
        ],
        if (legacy.giftEnd != null) ...[
          const SizedBox(height: 6),
          Text(
            'Hediye Pro erişiminiz ${DateFormat('dd.MM.yyyy').format(legacy.giftEnd!.toLocal())} tarihine kadar devam ediyor.',
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
        if (legacy.active)
          TextButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.settings_outlined, size: 18),
            label: const Text('Aboneliği yönet'),
          ),
      ],
    ),
  );
}
