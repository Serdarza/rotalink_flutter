import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/device_test_service.dart';
import '../services/device_test_messaging.dart';
import '../services/holiday_notification_scheduler.dart';
import '../theme/app_colors.dart';

class DeviceTestScreen extends StatefulWidget {
  const DeviceTestScreen({super.key});
  @override
  State<DeviceTestScreen> createState() => _DeviceTestScreenState();
}

class _DeviceTestScreenState extends State<DeviceTestScreen> {
  final _code = TextEditingController(), _service = DeviceTestService.instance;
  bool _busy = false;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    _service.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await work();
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e is FormatException
              ? e.message
              : 'İşlem tamamlanamadı (${DeviceTestMessaging.diagnosticCode(e)}).',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pair() async {
    String? token;
    final allowed = await HolidayNotificationScheduler.requestPermissions();
    try {
      token = await DeviceTestMessaging.token();
    } catch (_) {}
    await _service.pair(
      _code.text,
      fcmToken: token,
      platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    );
    _code.clear();
    if (mounted) {
      setState(
        () => _message = !allowed
            ? 'Pop-up testi hazır. Bildirim için telefon ayarlarından Rotalink iznini açın.'
            : token == null
            ? 'Pop-up testi hazır. FCM belirteci alınamadı; bildirim bağlantısını yeniden deneyin.'
            : 'Telefon bağlandı. Pop-up ve cihaz belirteci hazır.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yönetici testi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.phonelink_setup_rounded,
              size: 48,
              color: AppColors.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Yalnızca bu telefon',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'Bu ekran yalnızca test sürümünde bulunur. Paneldeki Telefon Testleri koduyla bağlanın. Taslaklar tüm kullanıcılara yayımlanmaz.',
            ),
            const SizedBox(height: 24),
            if (!_service.paired) ...[
              TextField(
                controller: _code,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Paneldeki eşleştirme kodu',
                  hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(_pair),
                icon: const Icon(Icons.link),
                label: const Text('Telefonu bağla'),
              ),
            ] else ...[
              Text(
                _service.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(_service.status),
              const SizedBox(height: 12),
              const Text(
                'Pop-up testi için uygulamayı açık tutun. Anlık bildirim testinde ana ekrana dönerek uygulamayı arka plana alabilirsiniz.',
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(_service.refresh),
                icon: const Icon(Icons.refresh),
                label: const Text('Testleri yenile'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final token = await DeviceTestMessaging.token();
                        if (token == null) {
                          throw const FormatException(
                            'FCM belirteci alınamadı.',
                          );
                        }
                        try {
                          await _service.updateFcm(token);
                        } catch (error) {
                          if (error is FormatException) rethrow;
                          throw FormatException(
                            'Telefon sunucuya kaydedilemedi (${DeviceTestMessaging.diagnosticCode(error)}).',
                          );
                        }
                        if (mounted) {
                          setState(
                            () => _message = 'Bildirim bağlantısı yenilendi.',
                          );
                        }
                      }),
                child: const Text('Bildirim bağlantısını yenile'),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await _service.resetPopupHistory();
                        if (mounted) {
                          setState(
                            () => _message =
                                'Pop-up geçmişi sıfırlandı. Panelden yeni test başlatın.',
                          );
                        }
                      }),
                child: const Text('Pop-up test geçmişini sıfırla'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await _service.disconnect();
                        await DeviceTestMessaging.stop();
                      }),
                child: const Text('Test bağlantısını kapat'),
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Text(_message, semanticsLabel: _message),
              ),
          ],
        ),
      ),
    );
  }
}
