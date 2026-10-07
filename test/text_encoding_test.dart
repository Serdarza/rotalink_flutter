import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rotalink_flutter/utils/text_encoding.dart';

void main() {
  const tr = 'Düzce Öğretmenevi · İstanbul Şişli · Çay ılık';

  test('charset olmayan yanıt da UTF-8 çözülür', () {
    final res = http.Response.bytes(utf8.encode(tr), 200, headers: const {'content-type': 'text/plain'});
    expect(res.body, isNot(tr));
    expect(responseText(res), tr);
  });

  test('Latin-1 diye kaydedilmiş önbellek onarılır', () {
    final bozuk = latin1.decode(utf8.encode(tr));
    expect(bozuk, contains('Ã¼'));
    expect(looksMojibake(bozuk), isTrue);
    expect(fixMojibake(bozuk), tr);
  });

  test('temiz metin değişmez', () {
    expect(fixMojibake(tr), tr);
    expect(looksMojibake(tr), isFalse);
  });
}
