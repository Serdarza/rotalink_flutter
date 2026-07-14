import 'dart:math';

/// KAMİ konuşma balonu mesaj havuzu.
///
/// Her uygulama oturumunda [pickRandomBubbleMessage] ile tek bir mesaj seçilir.
abstract final class KamiMessages {
  static const List<String> bubbleMessages = <String>[
    '💬 Size Rotalink veritabanından nasıl yardımcı olabilirim?',
    '🚗 İki il arası rota veya konumunuza göre rota önerebilirim.',
    '🏨 Yakınınızdaki kamu tesislerini veritabanından listeleyebilirim.',
    '☕ Belediye sosyal tesislerini gösterebilirim.',
    '🍽 İl bazında yöresel yemek önerilerini paylaşabilirim.',
    '🏛 Gezilecek yerleri veritabanından bulabilirim.',
    '🌿 Hafta sonu için yakın illeri önerebilirim.',
    '📍 Yol üzerindeki tesisleri haritada gösterebilirim.',
    '🔍 Tesis adı veya il ile arama yapabilirim.',
    '🧭 Tüm cevaplarım Rotalink veritabanından gelir.',
  ];

  /// Konum bilinmediğinde varsayılan hazır sorular.
  static const List<String> suggestionChips = <String>[
    '🚗 Yakınımdan rota öner',
    '🏨 Yakınımdaki tesisler',
    '🍽 Ne yemeliyim?',
    '🏛 Nereleri gezebilirim?',
    '🌿 Bu hafta sonu nereye gidebilirim?',
    '☕ Yakınımdaki belediye tesisleri',
  ];

  /// Kullanıcının bulunduğu ile göre hazır sorular.
  static List<String> suggestionChipsForCity(String city) {
    final c = city.trim();
    if (c.isEmpty) return suggestionChips;
    return <String>[
      '🚗 Yakınımdan rota öner',
      '🏨 Yakınımdaki tesisler',
      '🍽 $c\'de ne yemeliyim?',
      '🏛 $c gezilecek yerler',
      '🌿 Bu hafta sonu nereye gidebilirim?',
      '☕ Yakınımdaki belediye tesisleri',
    ];
  }

  static const String welcomeHeadline = 'Merhaba';
  static const String welcomeName = 'Ben KAMİ';
  static const String welcomeBody =
      'Türkiye genelinde kamu misafirhaneleri, belediye sosyal tesisleri, '
      'gezilecek yerler, yöresel yemekler ve rota planlamada yanınızdayım.';

  static const String welcomeTagline = 'Rotalink ile güvenli seyahat';
  static const String sourceLabel = 'Rotalink';
  static const String appBarTitle = 'KAMİ';
  static const String appBarSubtitle = 'Akıllı Kamu Seyahat Asistanı';
  static const String inputHint = 'Bana bir şey sor...';
  static const String fabTooltip = 'KAMİ — Akıllı seyahat asistanı';

  static String pickRandomBubbleMessage([Random? random]) {
    final rng = random ?? Random();
    return bubbleMessages[rng.nextInt(bubbleMessages.length)];
  }
}
