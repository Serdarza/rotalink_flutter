import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'ads/ad_service.dart';
import 'app.dart';
import 'bootstrap/firebase_bootstrap.dart';
import 'services/holiday_notification_scheduler.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await initializeFirebase();
  } catch (e) {
    debugPrint('Firebase başlatılamadı: $e');
  }

  try {
    await AdService.instance.initialize();
  } catch (e) {
    debugPrint('AdMob başlatılamadı: $e');
  }

  try {
    await initializeDateFormatting('tr_TR', null);
  } catch (e) {
    debugPrint('Tarih formatı başlatılamadı: $e');
  }

  try {
    await HolidayNotificationScheduler.initialize();
  } catch (e) {
    debugPrint('Bildirim zamanlayıcı başlatılamadı: $e');
  }

  // Native splash kurumsal renk; Flutter splash: fade ~0,9 sn + metin ~1,6 sn.
  runApp(const RotalinkApp());
}
