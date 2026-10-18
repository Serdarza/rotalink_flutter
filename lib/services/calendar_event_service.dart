import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Telefonun yerel takvimine "etkinlik ekle" ekranını açar.
///
/// Android: `CalendarContract` ACTION_INSERT (izin gerekmez).
/// iOS: `EKEventEditViewController` (kaydı kullanıcı onaylar).
/// Kayıt işlemini her zaman kullanıcı kendisi onaylar; uygulama takvime
/// kendiliğinden yazmaz.
abstract final class CalendarEventService {
  static const MethodChannel _channel = MethodChannel('rotalink/calendar');

  /// Etkinlik notuna eklenen bağlantı. Belirli bir tesise yönlenmez; uygulamayı
  /// (yüklüyse) normal açılış ekranıyla açar, değilse mağaza sayfasına götürür.
  static const String appLink = 'https://rotalink.tr/indir/';

  static String notesFor() => 'Rotalink uygulaması: $appLink';

  /// Düzenleme ekranını açar; açılamazsa false.
  static Future<bool> openEditor({
    required String title,
    required DateTime begin,
    Duration duration = const Duration(hours: 1),
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('addEvent', <String, Object>{
        'title': title,
        'notes': notesFor(),
        'beginMillis': begin.millisecondsSinceEpoch,
        'endMillis': begin.add(duration).millisecondsSinceEpoch,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      debugPrint('Calendar: ${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
