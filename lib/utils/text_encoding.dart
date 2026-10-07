import 'dart:convert';

import 'package:http/http.dart' as http;

/// Yanıt gövdesi her zaman UTF-8 çözülür. [http.Response.body] Content-Type'ta
/// charset yoksa (bazı operatör / proxy bunu siler) Latin-1 kullanır ve
/// "ü" → "Ã¼" bozulması olur.
String responseText(http.Response res) =>
    utf8.decode(res.bodyBytes, allowMalformed: true);

final _mojibake = RegExp('Ã[\u0080-\u00BF]|Ä[\u0080-\u00BF]|Å[\u0080-\u00BF]');

bool looksMojibake(String s) => _mojibake.hasMatch(s);

/// Daha önce Latin-1 diye çözülüp kaydedilmiş UTF-8 metni onarır; temizse aynen döner.
String fixMojibake(String s) {
  if (!looksMojibake(s)) return s;
  try {
    return utf8.decode(latin1.encode(s));
  } catch (_) {
    return s;
  }
}
