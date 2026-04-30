/// Kotlin [StringExtensions.normalizeForSearch].
String normalizeForSearch(String s) {
  var t = s
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('Ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('Ş', 's')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'u');
  t = t.toLowerCase();
  return t.replaceAll(' ', '');
}
