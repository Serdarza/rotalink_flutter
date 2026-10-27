import 'package:flutter/foundation.dart';

@immutable
class AdminPopup {
  const AdminPopup({
    required this.id,
    required this.version,
    required this.title,
    required this.body,
    required this.frequency,
    required this.priority,
    this.imageUrl,
    this.buttonLabel = '',
    this.link = '',
    this.route = '',
    this.startsAt,
    this.endsAt,
    this.deliveryId,
  });
  final String id, title, body, frequency, buttonLabel, link, route;
  final int version, priority;
  final Uri? imageUrl;
  final DateTime? startsAt, endsAt;
  final String? deliveryId;
  bool get isTest => deliveryId != null;
  String get historyKey => '$id:$version';
  static const routes = {
    '',
    'anasayfa',
    'kampanyalar',
    'tatiller',
    'kis-kesfet',
    'rota',
    'ara',
    'tesisler',
    'pro',
    'external',
  };
  static const origin = 'https://admin.rotalink.tr';
  factory AdminPopup.parse(Map<String, dynamic> p) {
    String str(String k, int max, {bool required = false}) {
      final v = p[k];
      if (v == null && !required) return '';
      if (v is! String || v.length > max || (required && v.trim().isEmpty)) {
        throw FormatException(k);
      }
      return v.trim();
    }

    final id = str('id', 80, required: true),
        title = str('title', 100, required: true),
        body = str('body', 20000, required: true),
        frequency = str('frequency', 20, required: true),
        route = str('route', 30),
        link = str('link', 1000);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id) ||
        p['version'] is! int ||
        (p['version'] as int) < 1 ||
        p['priority'] is! int ||
        !{'once', 'daily', 'every_launch'}.contains(frequency) ||
        !routes.contains(route)) {
      throw const FormatException('Pop-up alanları geçersiz.');
    }
    if (link.isNotEmpty) {
      final u = Uri.tryParse(link);
      if (u == null ||
          u.scheme != 'https' ||
          u.host.isEmpty ||
          u.userInfo.isNotEmpty) {
        throw const FormatException('Bağlantı geçersiz.');
      }
    }
    DateTime? date(String key) {
      final s = p[key];
      if (s == null || s == '') return null;
      if (s is! String) throw FormatException(key);
      return DateTime.parse(s).toUtc();
    }

    final start = date('startsAt'), end = date('endsAt');
    if (start != null && end != null && !end.isAfter(start)) {
      throw const FormatException('Tarih aralığı geçersiz.');
    }
    Uri? image;
    final raw = str('imageUrl', 1000);
    if (raw.isNotEmpty) {
      image = Uri.parse(origin).resolve(raw);
      if (image.origin != origin ||
          !RegExp(
            r'^/(device-test/media/[a-f0-9-]{36}|media/[a-f0-9-]{36}\.(webp|jpg|png))$',
          ).hasMatch(image.path) ||
          image.hasQuery ||
          image.hasFragment) {
        throw const FormatException('Görsel kaynağı geçersiz.');
      }
    }
    final delivery = str('deliveryId', 36);
    if (delivery.isNotEmpty && !RegExp(r'^[a-f0-9-]{36}$').hasMatch(delivery)) {
      throw const FormatException('Test kimliği geçersiz.');
    }
    return AdminPopup(
      id: id,
      version: p['version'],
      title: title,
      body: body,
      frequency: frequency,
      priority: p['priority'],
      imageUrl: image,
      buttonLabel: str('buttonLabel', 80),
      route: route,
      link: link,
      startsAt: start,
      endsAt: end,
      deliveryId: delivery.isEmpty ? null : delivery,
    );
  }
  bool eligible(DateTime at, Map<String, String> history, Set<String> closed) {
    if (closed.contains(historyKey) ||
        (startsAt != null && at.isBefore(startsAt!)) ||
        (endsAt != null && !at.isBefore(endsAt!))) {
      return false;
    }
    final seen = DateTime.tryParse(history[historyKey] ?? '');
    if (frequency == 'every_launch' || seen == null) return true;
    return frequency == 'daily' && istanbulDay(seen) != istanbulDay(at);
  }

  static String istanbulDay(DateTime at) => at
      .toUtc()
      .add(const Duration(hours: 3))
      .toIso8601String()
      .substring(0, 10);
}
