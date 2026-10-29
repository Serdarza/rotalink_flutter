import 'package:flutter/material.dart';

import '../billing/free_price_quota.dart';
import '../billing/premium_account_bridge.dart';
import '../billing/premium_auth_service.dart';
import '../billing/premium_presentation.dart';
import '../billing/premium_price_access.dart';
import '../billing/price_access.dart';
import '../billing/pro_service.dart';
import '../constants/facility_pricing.dart';
import '../models/kis_kesfet_place.dart';
import '../models/kis_kesfet_ucret.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../theme/app_colors.dart';
import 'kis_kesfet_ui.dart';

/// Termal ücreti, misafirhane fiyatı gibi tek tek açılır.
///
/// Eski Pro hepsini görür. Ücretsiz hak ve ücretli paket hakkı sunucuda düşer.
/// Resmî kaynak, ücretsiz hakla açılan tarifede görünmez.
String thermalPriceId(KisKesfetPlace place) => '${place.il}\u0001${place.isim}';

bool thermalPriceOpen(KisKesfetPlace place) =>
    PriceAccess.unlockedFor(thermalPriceId(place));

bool thermalSourceOpen(KisKesfetPlace place) {
  if (!thermalPriceOpen(place)) return false;
  if (PriceAccess.unlocked) return true;
  final account = ServerPremiumAccountBridge.instance.account;
  if (account?.plan == null) return false;
  final paid =
      account!.status == PremiumSubscriptionStatus.active ||
      account.status == PremiumSubscriptionStatus.renewalOff;
  return paid && PremiumPriceAccess.instance.contains(thermalPriceId(place));
}

Listenable get thermalPriceListenable => Listenable.merge([
  ProService.instance.isPro,
  FreePriceQuota.instance.unlockedIds,
  PremiumPriceAccess.instance.unlockedIds,
  ServerPremiumAccountBridge.instance,
]);

class KisKesfetUcretSummary extends StatelessWidget {
  const KisKesfetUcretSummary({super.key, required this.place});
  final KisKesfetPlace place;

  @override
  Widget build(BuildContext context) {
    final ucret = place.ucretBilgisi?.baslangicUcreti(DateTime.now());
    if (ucret == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: thermalPriceListenable,
      builder: (context, _) {
        if (!thermalPriceOpen(place)) {
          return const _ThermalPriceLock(compact: true);
        }
        return _openSummary(context, ucret);
      },
    );
  }

  Widget _openSummary(BuildContext context, KisKesfetUcret ucret) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KisKesfetUi.tintOf(context, place.kategori),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Başlangıç · ${ucret.tur.etiket}',
            style: TextStyle(
              color: AppColors.textStrongOf(context),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${ucret.fiyat} / ${ucret.birim}',
            style: TextStyle(
              color: KisKesfetUi.accentOf(context, place.kategori),
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [ucret.ad, if (ucret.kosul.isNotEmpty) ucret.kosul].join(' · '),
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class KisKesfetUcretSection extends StatelessWidget {
  const KisKesfetUcretSection({super.key, required this.place});
  final KisKesfetPlace place;

  @override
  Widget build(BuildContext context) {
    final bilgi = place.ucretBilgisi;
    final kalemler = bilgi?.gecerliKalemler(DateTime.now()) ?? const [];
    if (kalemler.isEmpty) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: thermalPriceListenable,
      builder: (context, _) {
        if (!thermalPriceOpen(place)) {
          return _ThermalPriceLock(place: place);
        }
        return _openSection(context, bilgi, kalemler);
      },
    );
  }

  Widget _openSection(
    BuildContext context,
    KisKesfetUcretBilgisi? bilgi,
    List<KisKesfetUcret> kalemler,
  ) {
    final accent = KisKesfetUi.accentOf(context, place.kategori);
    final muted = AppColors.textMutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ücretler',
          style: TextStyle(
            color: AppColors.textStrongOf(context),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        for (final tur in KisKesfetUcretTuru.values.where(
          (tur) => kalemler.any((k) => k.tur == tur),
        )) ...[
          Text(
            tur.etiket,
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final kalem in kalemler.where((k) => k.tur == tur))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.borderOf(context)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kalem.ad,
                    style: TextStyle(
                      color: AppColors.textStrongOf(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${kalem.fiyat} / ${kalem.birim}',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (kalem.kosul.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      kalem.kosul,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                  if (kalem.gecerlilikBitis.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Geçerlilik sonu: ${KisKesfetUi.formatDate(kalem.gecerlilikBitis)}',
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
        ],
        if (bilgi != null) ...[
          if (bilgi.aciklama.isNotEmpty)
            Text(
              bilgi.aciklama,
              style: TextStyle(color: muted, fontSize: 12, height: 1.5),
            ),
          const SizedBox(height: 8),
          Text(
            'Ücret son kontrol: ${KisKesfetUi.formatDate(bilgi.sonKontrol)}',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _ThermalPriceLock extends StatefulWidget {
  const _ThermalPriceLock({this.place, this.compact = false});

  final KisKesfetPlace? place;
  final bool compact;

  @override
  State<_ThermalPriceLock> createState() => _ThermalPriceLockState();
}

class _ThermalPriceLockState extends State<_ThermalPriceLock> {
  bool _unlocking = false;

  bool get _signedIn {
    final user = PremiumAuthService.instance.currentUser;
    return user != null && !user.isAnonymous;
  }

  bool get _paidPlan {
    final account = ServerPremiumAccountBridge.instance.account;
    if (account?.plan == null) return false;
    return account!.status == PremiumSubscriptionStatus.active ||
        account.status == PremiumSubscriptionStatus.renewalOff;
  }

  int get _freeRemaining {
    if (_signedIn) {
      return ServerPremiumAccountBridge.instance.account?.priceUsage?.remaining ??
          FreePriceQuota.instance.remaining;
    }
    return FreePriceQuota.instance.remaining;
  }

  Future<void> _openPro() async {
    await Navigator.of(context).pushNamed(RotalinkShellRoutes.pro);
  }

  Future<void> _openWithRight() async {
    final place = widget.place;
    if (place == null || _unlocking) return;
    setState(() => _unlocking = true);
    final id = thermalPriceId(place);
    String? message;
    var limitReached = false;
    if (_signedIn) {
      final result = await PremiumPriceAccess.instance.claim(
        facilityId: id,
        il: place.il,
        isim: place.isim,
      );
      message = result.message;
      limitReached = result.limitReached;
    } else {
      message = await FreePriceQuota.instance.unlock(id);
    }
    if (!mounted) return;
    setState(() => _unlocking = false);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
    if (limitReached) await _openPro();
  }

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.textMutedOf(context);
    final quota = ServerPremiumAccountBridge.instance.account?.priceUsage;
    final canSpend = _paidPlan
        ? quota == null || quota.unlimited || quota.remaining > 0
        : _freeRemaining > 0;
    final label = _paidPlan
        ? (canSpend ? 'Ücreti görmek için aç' : 'Paketleri incele')
        : FacilityPricing.freeRightsButton(canSpend ? _freeRemaining : 0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySoftOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  FacilityPricing.lockedTitle,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontWeight: FontWeight.w800,
                    fontSize: widget.compact ? 13 : 15,
                  ),
                ),
              ),
            ],
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 6),
            Text(
              _paidPlan
                  ? 'Açmak bu dönemin fiyat hakkından düşer. Resmî kaynak da o zaman görünür.'
                  : 'Açmak ücretsiz fiyat hakkından düşer. Resmî kaynak Pro ile görünür.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _unlocking
                    ? null
                    : () {
                        if (canSpend) {
                          _openWithRight();
                        } else {
                          _openPro();
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: _unlocking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(label),
              ),
            ),
            if (_paidPlan && quota != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Kalan hak ${quota.remaining} / ${quota.total}',
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
