import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:rotalink_flutter/billing/pro_products.dart';
import 'package:rotalink_flutter/billing/store_entitlement.dart';

void main() {
  final now = DateTime(2026, 10, 18, 12);

  StoreGrant decide({
    required String productId,
    required PurchaseStatus status,
    DateTime? expiry,
  }) =>
      StoreEntitlement.decide(
        productId: productId,
        status: status,
        expiry: expiry,
        now: now,
      );

  test('aylık satın alma Pro açar', () {
    expect(
      decide(
        productId: ProProducts.monthly,
        status: PurchaseStatus.purchased,
      ),
      StoreGrant.activate,
    );
  });

  test('yıllık satın alma Pro açar', () {
    expect(
      decide(
        productId: ProProducts.yearly,
        status: PurchaseStatus.purchased,
        expiry: now.add(const Duration(days: 365)),
      ),
      StoreGrant.activate,
    );
  });

  test('Play promo ve App Store offer aynı ürün kimliğiyle açılır', () {
    expect(ProProducts.ids, {ProProducts.monthly, ProProducts.yearly});
    expect(
      decide(
        productId: ProProducts.monthly,
        status: PurchaseStatus.restored,
        expiry: now.add(const Duration(days: 30)),
      ),
      StoreGrant.activate,
    );
    expect(
      decide(
        productId: ProProducts.yearly,
        status: PurchaseStatus.purchased,
      ),
      StoreGrant.activate,
    );
  });

  test('süresi bitmiş geri yükleme Pro açmaz', () {
    expect(
      decide(
        productId: ProProducts.monthly,
        status: PurchaseStatus.restored,
        expiry: now.subtract(const Duration(days: 1)),
      ),
      StoreGrant.ignoreExpiredRestore,
    );
  });

  test('iptal ve hata Pro açmaz', () {
    expect(
      decide(productId: ProProducts.yearly, status: PurchaseStatus.canceled),
      StoreGrant.canceled,
    );
    expect(
      decide(productId: ProProducts.monthly, status: PurchaseStatus.error),
      StoreGrant.failed,
    );
  });

  test('bilinmeyen ürün ve bekleyen ödeme hak vermez', () {
    expect(
      decide(productId: 'baska_urun', status: PurchaseStatus.purchased),
      StoreGrant.ignoreUnknownProduct,
    );
    expect(
      decide(productId: ProProducts.monthly, status: PurchaseStatus.pending),
      StoreGrant.pending,
    );
  });
}
