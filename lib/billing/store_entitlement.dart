import 'package:in_app_purchase/in_app_purchase.dart';

import 'pro_products.dart';

/// Mağaza satın alma kaydının Pro açıp açmayacağı.
///
/// Google Play promo kodu ve App Store abonelik teklif kodu, aynı ürün
/// kimlikleriyle (`rotalink_pro_monthly` / `rotalink_pro_yearly`) mağaza
/// tarafından `purchased` veya `restored` olarak gelir. Ayrı bir kupon
/// doğrulaması yoktur; hak yalnızca bu kararla verilir.
enum StoreGrant {
  activate,
  ignoreExpiredRestore,
  ignoreUnknownProduct,
  pending,
  failed,
  canceled,
}

abstract final class StoreEntitlement {
  static StoreGrant decide({
    required String productId,
    required PurchaseStatus status,
    DateTime? expiry,
    required DateTime now,
  }) {
    if (!ProProducts.ids.contains(productId)) {
      return StoreGrant.ignoreUnknownProduct;
    }
    switch (status) {
      case PurchaseStatus.pending:
        return StoreGrant.pending;
      case PurchaseStatus.error:
        return StoreGrant.failed;
      case PurchaseStatus.canceled:
        return StoreGrant.canceled;
      case PurchaseStatus.purchased:
        return StoreGrant.activate;
      case PurchaseStatus.restored:
        if (expiry != null && !expiry.isAfter(now)) {
          return StoreGrant.ignoreExpiredRestore;
        }
        return StoreGrant.activate;
    }
  }
}
