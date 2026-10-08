import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../constants/github_pro_code_config.dart';
import '../utils/text_encoding.dart';
import 'free_pass_device_guard.dart';
import 'pro_service.dart';

/// `pro_kodlar.json` içindeki tek kod kaydı. Kodun kendisi değil, özeti tutulur.
class GiftCodeEntry {
  const GiftCodeEntry({
    required this.ozet,
    required this.plan,
    this.sonKullanma,
    this.kullanim = 1,
  });

  final String ozet;

  /// `aylik` veya `yillik`.
  final String plan;

  /// Bu günden sonra kod kabul edilmez (gün sonuna kadar geçerli).
  final DateTime? sonKullanma;

  /// Kaç farklı cihazda kullanılabileceği.
  final int kullanim;

  Duration get sure => plan == 'yillik'
      ? const Duration(days: 365)
      : const Duration(days: 30);

  bool expiredAt(DateTime now) {
    final son = sonKullanma;
    return son != null &&
        now.isAfter(DateTime(son.year, son.month, son.day, 23, 59, 59));
  }

  static GiftCodeEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final ozet = raw['ozet'];
    final plan = raw['plan'];
    if (ozet is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(ozet)) {
      return null;
    }
    if (plan != 'aylik' && plan != 'yillik') return null;
    final son = raw['son_kullanma'];
    final kullanim = raw['kullanim'];
    return GiftCodeEntry(
      ozet: ozet,
      plan: plan as String,
      sonKullanma: son is String ? DateTime.tryParse(son) : null,
      kullanim: kullanim is int ? kullanim.clamp(1, 1000) : 1,
    );
  }
}

/// Hediye kodu kullanım sonucu.
class GiftRedeemResult {
  const GiftRedeemResult(this.ok, this.message);

  final bool ok;
  final String message;
}

/// Hediye Pro kodları: GitHub'daki özet listesiyle doğrulanır, kullanım
/// Firestore'da cihaz adına tek seferlik kaydedilir.
abstract final class ProGiftCodes {
  static const _userAgent = 'Rotalink-Flutter/1.0';
  static const _maxFailures = 5;
  static const _lockDuration = Duration(minutes: 2);

  static int _failures = 0;
  static DateTime? _lockedUntil;
  static bool _busy = false;

  /// Büyük harf, yalnız harf ve rakam: "ab12-cd34 ef56" → "AB12CD34EF56".
  static String normalize(String raw) =>
      raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  static String hash(String normalized) =>
      sha256.convert(utf8.encode('rotalink-pro-kod-v1:$normalized')).toString();

  static List<GiftCodeEntry> parse(String body) {
    final decoded = jsonDecode(body);
    final list = decoded is Map ? decoded['kodlar'] : null;
    if (list is! List) return const [];
    return [
      for (final raw in list) ?GiftCodeEntry.tryParse(raw),
    ];
  }

  static String planLabel(String? plan) =>
      plan == 'yillik' ? 'Yıllık' : 'Aylık';

  static String formatDate(DateTime d) {
    try {
      return DateFormat('d MMMM y', 'tr_TR').format(d);
    } catch (_) {
      return DateFormat('dd.MM.yyyy').format(d);
    }
  }

  static Future<GiftRedeemResult> redeem(String raw) async {
    if (_busy) return const GiftRedeemResult(false, 'Kod kontrol ediliyor…');
    final now = DateTime.now();
    final locked = _lockedUntil;
    if (locked != null && now.isBefore(locked)) {
      return const GiftRedeemResult(
        false,
        'Çok fazla hatalı deneme. Lütfen biraz sonra tekrar deneyin.',
      );
    }
    final code = normalize(raw);
    if (code.length < 6) {
      return const GiftRedeemResult(false, 'Kodu eksiksiz yazın.');
    }
    final pro = ProService.instance;
    if (pro.isPro.value) {
      return const GiftRedeemResult(
        false,
        'Zaten aktif bir Pro aboneliğiniz var.',
      );
    }

    _busy = true;
    try {
      final List<GiftCodeEntry> entries;
      try {
        final res = await http
            .get(
              GithubProCodeConfig.uri,
              headers: const {'User-Agent': _userAgent},
            )
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        entries = parse(responseText(res));
      } catch (e) {
        debugPrint('[Pro] kod listesi okunamadı: $e');
        return const GiftRedeemResult(
          false,
          'Kod doğrulanamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      }

      final codeHash = hash(code);
      GiftCodeEntry? entry;
      for (final e in entries) {
        if (e.ozet == codeHash) {
          entry = e;
          break;
        }
      }
      if (entry == null) {
        _failures++;
        if (_failures >= _maxFailures) {
          _failures = 0;
          _lockedUntil = now.add(_lockDuration);
        }
        return const GiftRedeemResult(false, 'Kod geçersiz.');
      }
      _failures = 0;
      if (entry.expiredAt(now)) {
        return const GiftRedeemResult(
          false,
          'Bu kodun kullanım süresi dolmuş.',
        );
      }

      final claim = await FreePassDeviceGuard.redeemGiftCode(
        codeHash: codeHash,
        maxUses: entry.kullanim,
      );
      final label = planLabel(entry.plan);
      switch (claim.kind) {
        case GiftClaimKind.granted:
          final current = pro.giftEndsAt.value;
          final base = current != null && current.isAfter(now) ? current : now;
          final end = base.add(entry.sure);
          await pro.grantGift(plan: entry.plan, end: end);
          return GiftRedeemResult(
            true,
            '$label hediye Pro açıldı. ${formatDate(end)} tarihine kadar '
            'tüm Pro özellikleri sizin.',
          );
        case GiftClaimKind.restored:
          final end = (claim.start ?? now).add(entry.sure);
          if (!end.isAfter(now)) {
            return const GiftRedeemResult(
              false,
              'Bu kod bu cihazda daha önce kullanıldı ve süresi doldu.',
            );
          }
          final current = pro.giftEndsAt.value;
          if (current == null || current.isBefore(end)) {
            await pro.grantGift(plan: entry.plan, end: end);
          }
          return GiftRedeemResult(
            true,
            '$label hediye Pro geri yüklendi. ${formatDate(end)} tarihine '
            'kadar geçerli.',
          );
        case GiftClaimKind.exhausted:
          return const GiftRedeemResult(false, 'Bu kod daha önce kullanılmış.');
        case GiftClaimKind.unavailable:
          return const GiftRedeemResult(
            false,
            'Kod şu anda doğrulanamadı. İnternet bağlantınızı kontrol edip '
            'tekrar deneyin.',
          );
      }
    } finally {
      _busy = false;
    }
  }
}
