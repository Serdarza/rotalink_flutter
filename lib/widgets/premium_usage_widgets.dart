import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../billing/premium_presentation.dart';
import '../theme/app_colors.dart';

/// Reusable in Premium now, and in a future account screen. Values are never
/// invented from the advertised plan limits when the account service is absent.
class PremiumUsageSummary extends StatelessWidget {
  const PremiumUsageSummary({
    super.key,
    required this.account,
    this.onManage,
    this.onChoosePlan,
  });

  final PremiumAccountSnapshot account;
  final VoidCallback? onManage;
  final VoidCallback? onChoosePlan;

  @override
  Widget build(BuildContext context) {
    final status = switch (account.status) {
      PremiumSubscriptionStatus.active =>
        account.plan == null ? 'Ücretsiz kullanım' : 'Aktif abonelik',
      PremiumSubscriptionStatus.renewalOff => 'Otomatik yenileme kapalı',
      PremiumSubscriptionStatus.pending => 'Ödeme bekleniyor',
      PremiumSubscriptionStatus.expired => 'Abonelik süresi doldu',
    };
    return Container(
      key: const ValueKey('premium-usage-summary'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  account.name,
                  style: TextStyle(
                    color: AppColors.textStrongOf(context),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              height: 1.4,
            ),
          ),
          if (account.periodEndsAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '${account.status == PremiumSubscriptionStatus.active ? 'Dönem sonu' : 'Bitiş tarihi'}: '
              '${DateFormat('dd.MM.yyyy').format(account.periodEndsAt!.toLocal())}',
              style: TextStyle(
                color: AppColors.textMutedOf(context),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _UsageMeter(label: 'Fiyat görüntüleme', quota: account.priceUsage),
          const SizedBox(height: 16),
          _UsageMeter(label: 'Yakın tesis araması', quota: account.nearbyUsage),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (onManage != null && account.plan != null)
                TextButton.icon(
                  onPressed: onManage,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Aboneliği yönet'),
                ),
              if (onChoosePlan != null && account.plan != null)
                TextButton.icon(
                  onPressed: onChoosePlan,
                  icon: const Icon(Icons.upgrade_rounded, size: 19),
                  label: Text(
                    account.plan == null
                        ? 'Paketleri incele'
                        : account.plan == PremiumPlan.platinum ||
                              account.plan == PremiumPlan.legacyPlatinum
                        ? 'Paketleri karşılaştır'
                        : 'Paket yükselt',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageMeter extends StatelessWidget {
  const _UsageMeter({required this.label, required this.quota});
  final String label;
  final PremiumQuotaSnapshot? quota;

  @override
  Widget build(BuildContext context) {
    final value = quota;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textStrongOf(context),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (value != null && value.unlimited)
              Text(
                'Sınırsız',
                style: TextStyle(
                  color: AppColors.textMutedOf(context),
                  fontSize: 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
          if (value != null && value.unlimited)
            Text(
              'Bu hak pakette sınırsız.',
              style: TextStyle(
                color: AppColors.textMutedOf(context),
                fontSize: 12,
              ),
            )
          else if (value != null) ...[
          Semantics(
            label: RightsWording.balance(
              kind: label,
              total: value.total,
              remaining: value.remaining,
              used: value.used,
            ),
            child: ExcludeSemantics(
              child: LinearProgressIndicator(
                value: value.progress,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
                backgroundColor: AppColors.primarySoftOf(context),
                color: value.remaining == 0
                    ? AppColors.warning
                    : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            RightsWording.balance(
              kind: label,
              total: value.total,
              remaining: value.remaining,
              used: value.used,
            ),
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ] else
          Text(
            'Kullanım bilgisi alınamadı.',
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

/// Only renders an upsell when a real account response reports exhaustion.
/// It neither blocks the caller nor changes any entitlement/usage counter.
class PremiumLimitNotice extends StatelessWidget {
  const PremiumLimitNotice({
    super.key,
    required this.account,
    required this.feature,
    required this.onChoosePlan,
  });
  final PremiumAccountSnapshot account;
  final PremiumLimitedFeature feature;
  final VoidCallback onChoosePlan;

  @override
  Widget build(BuildContext context) {
    final quota = feature == PremiumLimitedFeature.nearby
        ? account.nearbyUsage
        : account.priceUsage;
    if (quota == null || quota.remaining > 0) return const SizedBox.shrink();
    final nearby = feature == PremiumLimitedFeature.nearby;
    final free = account.plan == null;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primarySoftOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            nearby ? Icons.travel_explore_rounded : Icons.payments_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(height: 10),
          Text(
            nearby
                ? 'Daha Fazla Konum Keşfedin'
                : 'Daha Fazla Fiyat Görüntüleyin',
            style: TextStyle(
              color: AppColors.textStrongOf(context),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nearby && free
                ? 'Ücretsiz konum arama hakkınızı kullandınız. Rotalink Premium ile daha fazla kamu misafirhanesini keşfedin.'
                : nearby
                ? 'Ücretsiz konum arama hakkınızı kullandınız. Rotalink Pro ile daha fazla kamu misafirhanesini keşfedin.'
                : free
                ? 'Ücretsiz tesis fiyatı hakkınızı kullandınız. Rotalink Premium paketlerini inceleyebilirsiniz.'
                : 'Bu dönemin fiyat görüntüleme hakkını kullandınız. Size uygun diğer paketleri inceleyebilirsiniz.',
            style: TextStyle(
              color: AppColors.textMutedOf(context),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onChoosePlan,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('Paketleri incele'),
          ),
        ],
      ),
    );
  }
}
