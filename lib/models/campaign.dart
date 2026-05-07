import 'package:cloud_firestore/cloud_firestore.dart';

/// Kotlin [Campaign] — Firestore `KAMPANYALAR` belgesi.
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

  factory Campaign.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
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
    final ts = d['tarih'] is Timestamp
        ? d['tarih'] as Timestamp
        : (d['eklenmeTarihi'] is Timestamp ? d['eklenmeTarihi'] as Timestamp : null);

    return Campaign(
      id: doc.id,
      title: title,
      organization: org,
      summary: summary,
      linkUrl: link?.isEmpty ?? true ? null : link,
      createdAt: ts?.toDate(),
      tags: _tagsFromDoc(d, org),
    );
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
