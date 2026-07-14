/// GitHub `versiyon_güncellem.json` içeriği.
class AppVersionPolicy {
  const AppVersionPolicy({
    required this.androidLatestBuild,
    required this.iosLatestBuild,
    this.message,
    this.playStoreUrl,
    this.appStoreUrl,
  });

  final int androidLatestBuild;
  final int iosLatestBuild;
  final String? message;
  final String? playStoreUrl;
  final String? appStoreUrl;

  factory AppVersionPolicy.fromJson(Map<String, dynamic> json) {
    int readBuild(dynamic v, int fallback) {
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '') ?? fallback;
    }

    final android = readBuild(
      json['android_latest_build'] ?? json['android_build'] ?? json['latest_version_code'],
      1,
    );
    final ios = readBuild(
      json['ios_latest_build'] ?? json['ios_build'] ?? json['latest_version_code'],
      android,
    );
    final msg = json['mesaj'] ?? json['message'];
    final playStore = json['play_store'] ?? json['playStore'];
    final appStore = json['app_store'] ?? json['appStore'];

    String? readUrl(dynamic v) {
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) return null;
      return s;
    }

    return AppVersionPolicy(
      androidLatestBuild: android,
      iosLatestBuild: ios,
      message: readUrl(msg),
      playStoreUrl: readUrl(playStore),
      appStoreUrl: readUrl(appStore),
    );
  }
}
