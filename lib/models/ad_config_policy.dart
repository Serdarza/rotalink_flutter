/// GitHub `reklam_ayar.json` içeriği.
class AdConfigPolicy {
  const AdConfigPolicy({required this.cooldownMinutes});

  final int cooldownMinutes;

  factory AdConfigPolicy.fromJson(Map<String, dynamic> json) {
    final raw = json['reklam_bekleme_suresi'] ??
        json['bekleme_dakika'] ??
        json['cooldown_minutes'];
    int minutes;
    if (raw is int) {
      minutes = raw;
    } else {
      minutes = int.tryParse(raw?.toString() ?? '') ?? 5;
    }
    return AdConfigPolicy(cooldownMinutes: minutes.clamp(1, 60));
  }
}
