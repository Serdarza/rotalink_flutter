import 'package:cloud_firestore/cloud_firestore.dart';

/// Kotlin [Campaign] — GitHub kampanya.json / eski Firestore alan eşlemesi.
class Campaign {
  const Campaign({
    required this.id,
    required this.title,
    required this.organization,
    required this.summary,
    required this.linkUrl,
    required this.createdAt,
    required this.tags,
  });

  final String id;
  final String title;
  final String organization;
  final String summary;
  final String? linkUrl;
  final DateTime? createdAt;
  final List<String> tags;

  factory Campaign.fromMap(Map<String, dynamic> d, {required String id}) {
    final link = _firstNonBlankString([
      d['link'],
      d['detayLink'],
      d['detaylink'],
    ]);
    final titleRaw = _string(d['kampanyaBaslik'])?.trim();
    final title = (titleRaw != null && titleRaw.isNotEmpty)
        ? titleRaw
        : (_string(d['baslik']) ?? '').trim();
    final org = _firstNonBlankString([
      d['kurum'],
      d['kurulus'],
      d['kampanyaKurumu'],
    ]) ?? '';
    final summary = _string(d['aciklama']) ?? '';
    final ts = d['tarih'];
    DateTime? createdAt;
    if (ts is Timestamp) {
      createdAt = ts.toDate();
    } else if (ts is String) {
      createdAt = DateTime.tryParse(ts);
    } else if (d['eklenmeTarihi'] is Timestamp) {
      createdAt = (d['eklenmeTarihi'] as Timestamp).toDate();
    }

    return Campaign(
      id: id,
      title: title,
      organization: org,
      summary: summary,
      linkUrl: link?.isEmpty ?? true ? null : link,
      createdAt: createdAt,
      tags: _tagsFromDoc(d, org),
    );
  }

  factory Campaign.fromJson(Map<String, dynamic> json, {String? id, int? index}) {
    final title = (_string(json['baslik']) ?? _string(json['kampanyaBaslik']) ?? '')
        .trim();
    final resolvedId = id ??
        _string(json['id'])?.trim() ??
        (index != null ? 'kampanya-$index' : 'kampanya-${title.hashCode.abs()}');
    return Campaign.fromMap(json, id: resolvedId);
  }

  /// GitHub `kampanya.json` kök nesnesinden sıralı kampanya listesi.
  static List<Campaign> parseListFromRoot(dynamic root) {
    if (root is! Map) return const [];
    final raw = root['kampanyalar'];
    if (raw is! List) return const [];

    final out = <Campaign>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final campaign = Campaign.fromJson(map, index: i);
      if (campaign.title.trim().isEmpty) continue;
      out.add(campaign);
    }

    out.sort((a, b) {
      final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return out;
  }

  static String? _string(dynamic v) => v?.toString();

  static String? _firstNonBlankString(List<dynamic> keys) {
    for (final v in keys) {
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  static List<String> _tagsFromDoc(Map<String, dynamic> d, String organization) {
    final seen = <String>{};
    final out = <String>[];
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || seen.contains(t)) return;
      seen.add(t);
      out.add(t);
    }
    if (organization.trim().isNotEmpty) add(organization);
    final e = d['etiketler'];
    if (e is String) {
      for (final part in e.split(',')) {
        add(part);
      }
    } else if (e is List) {
      for (final x in e) {
        add(x?.toString() ?? '');
      }
    }
    return out;
  }
}
