import 'package:shared_preferences/shared_preferences.dart';

import '../models/campaign_insights.dart';

/// Keşfet'te kullanıcının seçtiği kamu personeli grubu (uygulama yeniden açıldığında korunur).
abstract final class CampaignFilterPrefs {
  static const _kAudience = 'rotalink_kampanya_audience_filter';

  static Future<CampaignAudience?> getAudience() async {
    final p = await SharedPreferences.getInstance();
    return CampaignAudience.byName(p.getString(_kAudience));
  }

  static Future<void> setAudience(CampaignAudience? audience) async {
    final p = await SharedPreferences.getInstance();
    if (audience == null) {
      await p.remove(_kAudience);
    } else {
      await p.setString(_kAudience, audience.name);
    }
  }
}
