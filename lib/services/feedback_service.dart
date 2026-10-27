import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../models/admin_popup.dart';

enum FeedbackKind {
  bug('Hata bildir'),
  complaint('Şikâyet gönder'),
  incorrectInfo('Yanlış bilgi bildir'),
  suggestion('Öneri paylaş'),
  newFacility('Yeni tesis öner');

  const FeedbackKind(this.label);
  final String label;
}

class FeedbackException implements Exception {
  const FeedbackException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All forms share this gateway. Firestore remains inaccessible to public clients.
class FeedbackService {
  FeedbackService({
    http.Client? client,
    FlutterSecureStorage? storage,
    Future<String> Function()? version,
  }) : _client = client ?? http.Client(),
       _storage = storage ?? const FlutterSecureStorage(),
       _version = version ?? _appVersion;
  static final instance = FeedbackService();
  final http.Client _client;
  final FlutterSecureStorage _storage;
  final Future<String> Function() _version;
  static const senderKey = 'rotalink_feedback_sender_v1';
  final _pending = <String, String>{};
  Future<String>? _senderFlight;
  bool _sending = false;
  DateTime? _lastSent;
  static String _randomId() => List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  static Future<String> _appVersion() async {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  }

  Future<String> _sender() =>
      _senderFlight ??= _loadSender().whenComplete(() => _senderFlight = null);
  Future<String> _loadSender() async {
    final value = await _storage.read(key: senderKey);
    if (value != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      return value;
    }
    final id = _randomId();
    await _storage.write(key: senderKey, value: id);
    return id;
  }

  static String? validateContact(String email, bool consent) {
    if (email.trim().isEmpty) return null;
    if (email.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())) {
      return 'Geçerli bir e-posta adresi yazın veya alanı boş bırakın.';
    }
    if (!consent) {
      return 'E-posta ile geri dönüş için kullanım izni verin veya e-posta alanını boş bırakın.';
    }
    return null;
  }

  Future<String> submit({
    required FeedbackKind kind,
    required String description,
    required String sourcePage,
    String email = '',
    bool contactConsent = false,
    String facilityId = '',
    String facilityName = '',
  }) async {
    final text = description.trim();
    if (text.length < 3 || text.length > 6000) {
      throw const FeedbackException(
        'Açıklama 3–6000 karakter arasında olmalı.',
      );
    }
    final contactError = validateContact(email, contactConsent);
    if (contactError != null) throw FeedbackException(contactError);
    if (_sending) throw const FeedbackException('Gönderim devam ediyor.');
    if (_lastSent != null &&
        DateTime.now().difference(_lastSent!) < const Duration(seconds: 30)) {
      throw const FeedbackException('Yeni bildirim için 30 saniye bekleyin.');
    }
    _sending = true;
    try {
      final fields = <String, dynamic>{
        'type': kind.name,
        'description': text,
        'email': email.trim(),
        'contactConsent': email.trim().isNotEmpty && contactConsent,
        'sourcePage': sourcePage,
        'facilityId': facilityId,
        'facilityName': facilityName,
        'appVersion': await _version(),
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      };
      final hash = sha256.convert(utf8.encode(jsonEncode(fields))).toString();
      if (_pending.length > 20) _pending.remove(_pending.keys.first);
      final id = _pending.putIfAbsent(hash, _randomId);
      final response = await _client
          .post(
            Uri.parse('${AdminPopup.origin}/public/feedback'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({...fields, 'id': id, 'sender': await _sender()}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw FeedbackException(switch (response.statusCode) {
          429 => 'Gönderim sınırına ulaşıldı. Bir süre sonra tekrar deneyin.',
          404 || 405 || 501 =>
            'Bildirim bağlantısı henüz etkin değil. Yönetim panelindeki gönderim bağlantısının tamamlanması gerekiyor. Yazdıklarınız bu formda korunuyor.',
          401 || 403 =>
            'Bildirim servisi bu gönderime izin vermedi. Yönetim panelindeki bağlantı ayarlarının kontrol edilmesi gerekiyor. Yazdıklarınız bu formda korunuyor.',
          503 =>
            'Bildirim servisi şu anda kullanılamıyor. Yazdıklarınız bu formda korunuyor.',
          _ =>
            'Bildirim gönderilemedi. Bilgilerinizi kontrol edip tekrar deneyin.',
        });
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['id'] != id || body['accepted'] != true) {
        throw const FeedbackException(
          'Gönderim doğrulanamadı. Tekrar deneyin.',
        );
      }
      _pending.remove(hash);
      _lastSent = DateTime.now();
      return id;
    } on FeedbackException {
      rethrow;
    } catch (_) {
      throw const FeedbackException(
        'Bağlantı kurulamadı. Yazdıklarınız bu formda korunuyor; tekrar deneyebilirsiniz.',
      );
    } finally {
      _sending = false;
    }
  }
}
