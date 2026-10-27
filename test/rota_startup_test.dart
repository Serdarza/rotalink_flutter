import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rotalink_flutter/data/firebase_rota_repository.dart';

String database(String name) => jsonEncode({
  'tesisler': [
    {'isim': name, 'il': 'Ankara', 'enlem': 39.9, 'boylam': 32.8},
  ],
});

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const network = MethodChannel('dev.fluttercommunity.plus/connectivity');
  late Directory directory;
  late bool connected;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rotalink_startup_');
    connected = true;
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      paths,
      (_) async => directory.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      network,
      (_) async => [connected ? 'wifi' : 'none'],
    );
  });

  tearDown(() async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(network, null);
    await directory.delete(recursive: true);
  });

  test(
    'ilk açılış yanıt vermeyen ağı beklemez; güncel veri tüm dinleyicilere gelir',
    () async {
      final response = Completer<http.Response>();
      final requested = Completer<void>();
      final versionRequested = Completer<void>();
      var downloads = 0;
      await http.runWithClient(
        () async {
          final repository = FirebaseRotaRepository();
          final firstEvents = <RotaDataState>[];
          final secondEvents = <RotaDataState>[];
          final refreshed = Completer<void>();
          final secondRefreshed = Completer<void>();
          final first = repository.watchRoot().listen((state) {
            firstEvents.add(state);
            if (state.aramaIcinTumTesisler.singleOrNull?.isim ==
                'Güncel tesis') {
              refreshed.complete();
            }
          });
          addTearDown(first.cancel);

          // İndirme cevabını vermeden içerik hazır olmalı.
          await repository.ensureLocalDataReady().timeout(
            const Duration(seconds: 5),
          );
          await requested.future.timeout(const Duration(seconds: 5));
          expect(response.isCompleted, isFalse);
          expect(repository.currentState!.aramaIcinTumTesisler, isNotEmpty);
          expect(repository.currentState!.gezi, isNotEmpty);
          expect(repository.currentState!.loadedFromLocalCache, isTrue);

          final second = repository.watchRoot().listen((state) {
            secondEvents.add(state);
            if (state.aramaIcinTumTesisler.singleOrNull?.isim ==
                'Güncel tesis') {
              secondRefreshed.complete();
            }
          });
          addTearDown(second.cancel);
          await Future<void>.delayed(Duration.zero);
          expect(secondEvents.first, same(repository.currentState));
          expect(firstEvents.first, same(repository.currentState));
          response.complete(
            http.Response.bytes(utf8.encode(database('Güncel tesis')), 200),
          );
          await Future.wait([
            refreshed.future,
            secondRefreshed.future,
          ]).timeout(const Duration(seconds: 5));
          expect(
            repository.currentState!.aramaIcinTumTesisler.single.isim,
            'Güncel tesis',
          );
          expect(repository.currentState!.loadedFromLocalCache, isFalse);
          expect(downloads, 1);
          expect(
            jsonDecode(
              await File(
                '${directory.path}/rotalink_rota_root.json',
              ).readAsString(),
            )['tesisler'][0]['isim'],
            'Güncel tesis',
          );
          await versionRequested.future.timeout(const Duration(seconds: 5));
          await Future<void>.delayed(Duration.zero);
        },
        () => MockClient((request) {
          if (request.method == 'HEAD') {
            versionRequested.complete();
            return Future.value(
              http.Response('', 200, headers: {'etag': 'v2'}),
            );
          }
          downloads++;
          requested.complete();
          return response.future;
        }),
      );
    },
  );

  test(
    'güncel yerel önbellek kullanılır ve aynı veri tekrar indirilmez',
    () async {
      await File(
        '${directory.path}/rotalink_rota_root.json',
      ).writeAsString(database('Önbellekteki tesis'));
      SharedPreferences.setMockInitialValues({
        'rotalink_rota_last_version_check_ms':
            DateTime.now().millisecondsSinceEpoch,
      });
      var requests = 0;
      await http.runWithClient(
        () async {
          final repository = FirebaseRotaRepository();
          final states = await Future.wait([
            repository.watchRoot().first,
            repository.watchRoot().first,
          ]);
          expect(
            states.first.aramaIcinTumTesisler.single.isim,
            'Önbellekteki tesis',
          );
          expect(states.first, same(states.last));
          await Future<void>.delayed(Duration.zero);
          expect(requests, 0);
        },
        () => MockClient((_) async {
          requests++;
          return http.Response('', 503);
        }),
      );
    },
  );

  test('bozuk önbellek ve internet yokken gömülü veriyle açılır', () async {
    connected = false;
    await File(
      '${directory.path}/rotalink_rota_root.json',
    ).writeAsString('{bozuk');
    final repository = FirebaseRotaRepository();
    final state = await repository.watchRoot().first.timeout(
      const Duration(seconds: 5),
    );
    expect(state.initialLoadCompleted, isTrue);
    expect(state.aramaIcinTumTesisler, isNotEmpty);
    expect(state.gezi, isNotEmpty);
    expect(state.loadedFromLocalCache, isTrue);
    await Future<void>.delayed(Duration.zero);
  });
}
