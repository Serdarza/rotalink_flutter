/// Presentation only: extracts the minimum from a numeric TL price/range.
/// Non-price text remains unparsed; original tariffs and calculations are untouched.
double? minimumPriceAmount(String value) {
  final match = RegExp(
    r'^\s*(?:₺\s*)?(\d[\d., ]*)\s*(?:TL|₺)?\s*(?:[-–—]\s*(?:₺\s*)?(\d[\d., ]*)\s*(?:TL|₺)?)?\s*(?:(?:/\s*)?(?:kişi başı|oda başı|gecelik|gece)(?:\s*/\s*gece)?)?\s*$',
    caseSensitive: false,
  ).firstMatch(value.replaceAll('\u00a0', ' '));
  if (match == null) return null;
  double? parse(String raw) {
    var normalized = raw.trim().replaceAll(' ', '');
    if (normalized.contains(',')) {
      normalized = normalized.replaceAll('.', '').replaceAll(',', '.');
    } else if (RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(normalized)) {
      normalized = normalized.replaceAll('.', '');
    }
    final amount = double.tryParse(normalized);
    return amount != null && amount.isFinite && amount >= 0 ? amount : null;
  }

  final first = parse(match.group(1)!);
  final secondText = match.group(2);
  if (first == null || secondText == null) return first;
  final second = parse(secondText);
  if (second == null) return null;
  return first < second ? first : second;
}
