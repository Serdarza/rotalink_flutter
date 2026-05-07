import 'package:flutter/material.dart';

/// Kotlin [CampaignSmartIcon] ile aynı anahtar kelime + HSV mantığı.
IconData campaignSmartIconData(String title, String summary) {
  final text = '$title $summary'.toLowerCase();
  bool any(Set<String> words) => words.any((w) => text.contains(w));
  if (any(_shopping)) return Icons.shopping_bag;
  if (any(_food)) return Icons.restaurant;
  if (any(_lodging)) return Icons.hotel;
  if (any(_transport)) return Icons.directions_bus;
  return Icons.local_offer;
}

Color campaignSmartIconTint(String title, String summary) {
  final hue = _hueFromKey('$title|$summary');
  return HSVColor.fromAHSV(1, hue, 0.38, 0.55).toColor();
}

Color campaignSmartIconBackground(String title, String summary) {
  final hue = _hueFromKey('$title|$summary');
  return HSVColor.fromAHSV(1, hue, 0.22, 0.94).toColor();
}

double _hueFromKey(String key) {
  var h = key.hashCode;
  if (h == -2147483648) h = 0;
  return (h.abs() % 360).toDouble();
}

const _shopping = {
  'giyim',
  'ayakkabı',
  'ayakkabi',
  'mağaza',
  'magaza',
  'butik',
  'alışveriş',
  'alisveris',
};
const _food = {
  'yemek',
  'restoran',
  'kafe',
  'cafe',
  'tatlı',
  'tatli',
  'kahve',
  'menü',
  'menu',
  'lokanta',
};
const _lodging = {
  'otel',
  'misafirhane',
  'konaklama',
  'pansiyon',
  'hostel',
};
const _transport = {
  'bilet',
  'ulaşım',
  'ulasim',
  'araç',
  'arac',
  'otobüs',
  'otobus',
  'metro',
  'tren',
  'uçak',
  'ucak',
};
