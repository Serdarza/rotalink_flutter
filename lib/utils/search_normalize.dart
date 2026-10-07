/// Kotlin [StringExtensions.normalizeForSearch].
///
/// Bazı klavyeler "ü"/"İ" harflerini taban harf + birleşen işaret (U+0308, U+0307)
/// olarak gönderir; bu işaretler atılır ki "düzce" her iki biçimde de eşleşsin.
String normalizeForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x0300 && r <= 0x036F) continue;
    final c = String.fromCharCode(r);
    final f = _fold[c];
    if (f != null) {
      b.write(f);
    } else if (c != ' ') {
      b.write(c.toLowerCase());
    }
  }
  return b.toString();
}

const _fold = <String, String>{
  'ç': 'c',
  'Ç': 'c',
  'ğ': 'g',
  'Ğ': 'g',
  'ı': 'i',
  'İ': 'i',
  'ö': 'o',
  'Ö': 'o',
  'ş': 's',
  'Ş': 's',
  'ü': 'u',
  'Ü': 'u',
  'â': 'a',
  'Â': 'a',
  'î': 'i',
  'Î': 'i',
  'û': 'u',
  'Û': 'u',
};
