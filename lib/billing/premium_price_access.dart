import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'premium_account_bridge.dart';
import 'premium_auth_service.dart';

/// Server-verified price reveals for signed-in Free and Premium accounts.
///
/// Legacy Pro stays on [ProService] and is not rewritten here. The local set is
/// only a display cache of claims the server already accepted.
class PremiumPriceAccess {
  PremiumPriceAccess._();

  static final PremiumPriceAccess instance = PremiumPriceAccess._();
  static final Uri _claimUri = Uri.parse(
    'https://admin.rotalink.tr/api/premium/prices/claim',
  );

  final ValueNotifier<List<String>> unlockedIds = ValueNotifier<List<String>>(
    const [],
  );
  String? _uid;
  bool _claiming = false;

  bool contains(String facilityId) => unlockedIds.value.contains(facilityId);

  Future<void> initialize() async {
    PremiumAuthService.instance.userChanges.listen((user) {
      unawaited(_load(user?.isAnonymous == true ? null : user?.uid));
    }, onError: (Object error) => debugPrint('[Premium] fiyat önbelleği: $error'));
  }

  Future<void> _load(String? uid) async {
    _uid = uid;
    if (uid == null || uid.isEmpty) {
      unlockedIds.value = const [];
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      unlockedIds.value = List.unmodifiable(
        prefs.getStringList(_key(uid)) ?? const <String>[],
      );
    } catch (error) {
      debugPrint('[Premium] fiyat önbelleği okunamadı: $error');
    }
  }

  String _key(String uid) => 'rotalink_premium_price_ids_$uid';

  /// Returns null when the price is open. A non-null string is the user message.
  /// [limitReached] tells the caller to show the Premium plans.
  Future<({String? message, bool limitReached})> claim({
    required String facilityId,
    required String il,
    required String isim,
  }) async {
    if (contains(facilityId)) return (message: null, limitReached: false);
    if (_claiming) {
      return (message: 'İşlem sürüyor, lütfen bekleyin.', limitReached: false);
    }
    _claiming = true;
    try {
      final token = await PremiumAuthService.instance.freshIdToken();
      final response = await http
          .post(
            _claimUri,
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
              'accept': 'application/json',
            },
            body: jsonEncode({'il': il, 'isim': isim}),
          )
          .timeout(const Duration(seconds: 25));
      final Object? value;
      try {
        value = jsonDecode(response.body);
      } catch (_) {
        return (
          message: 'Fiyat servisine ulaşılamadı. Daha sonra tekrar deneyin.',
          limitReached: false,
        );
      }
      if (value is! Map) {
        return (
          message: 'Fiyat servisi geçersiz yanıt verdi.',
          limitReached: false,
        );
      }
      if (value['priced'] == false) {
        return (
          message:
              'Bu tesis için kayıtlı bir fiyat bulunamadı. Kullanım hakkı düşülmedi.',
          limitReached: false,
        );
      }
      if (response.statusCode == 429) {
        return (
          message: 'Fiyat görüntüleme hakkınız doldu.',
          limitReached: true,
        );
      }
      if (response.statusCode != 200 || value['accepted'] != true) {
        return (
          message: value['error'] is String
              ? value['error'] as String
              : 'Fiyat açılamadı. Daha sonra tekrar deneyin.',
          limitReached: false,
        );
      }
      final uid = _uid ?? PremiumAuthService.instance.currentUser?.uid;
      final ids = [...unlockedIds.value, facilityId];
      unlockedIds.value = List.unmodifiable(ids);
      if (uid != null && uid.isNotEmpty) {
        _uid = uid;
        try {
          await (await SharedPreferences.getInstance()).setStringList(
            _key(uid),
            ids,
          );
        } catch (error) {
          debugPrint('[Premium] fiyat önbelleği yazılamadı: $error');
        }
      }
      try {
        await ServerPremiumAccountBridge.instance.refresh();
      } catch (_) {}
      return (message: null, limitReached: false);
    } on StateError catch (error) {
      return (
        message: error.message.toString(),
        limitReached: false,
      );
    } catch (_) {
      return (
        message: 'Fiyat açılamadı. İnternet bağlantınızı kontrol edin.',
        limitReached: false,
      );
    } finally {
      _claiming = false;
    }
  }
}
