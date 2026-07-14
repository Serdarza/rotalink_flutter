import 'dart:convert';
import 'dart:io';

void main() {
  final inputPath = '.tmp_firestore_kampanyalar.json';
  final outputPath = 'discover_campaigns.json';

  final raw = jsonDecode(File(inputPath).readAsStringSync()) as Map<String, dynamic>;
  final docs = (raw['documents'] as List<dynamic>? ?? []);

  String? fieldString(Map<String, dynamic>? fields, String key) {
    final v = fields?[key];
    if (v is Map && v['stringValue'] != null) {
      return v['stringValue'].toString();
    }
    return null;
  }

  String? fieldTimestamp(Map<String, dynamic>? fields, String key) {
    final v = fields?[key];
    if (v is Map && v['timestampValue'] != null) {
      return v['timestampValue'].toString();
    }
    return null;
  }

  String? firstNonBlank(List<String?> values) {
    for (final v in values) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  List<String> tagsFromFields(Map<String, dynamic>? fields, String organization) {
    final seen = <String>{};
    final out = <String>[];
    void add(String s) {
      final t = s.trim();
      if (t.isEmpty || seen.contains(t)) return;
      seen.add(t);
      out.add(t);
    }

    if (organization.trim().isNotEmpty) add(organization);

    final e = fields?['etiketler'];
    if (e is Map && e['stringValue'] != null) {
      for (final part in e['stringValue'].toString().split(',')) {
        add(part);
      }
    } else if (e is Map && e['arrayValue'] is Map) {
      final values = (e['arrayValue'] as Map)['values'];
      if (values is List) {
        for (final x in values) {
          if (x is Map && x['stringValue'] != null) {
            add(x['stringValue'].toString());
          }
        }
      }
    }
    return out;
  }

  final kampanyalar = <Map<String, dynamic>>[];

  for (final doc in docs) {
    if (doc is! Map<String, dynamic>) continue;
    final name = doc['name']?.toString() ?? '';
    final id = name.split('/').last;
    final fields = doc['fields'] as Map<String, dynamic>?;

    final baslik = firstNonBlank([
      fieldString(fields, 'kampanyaBaslik'),
      fieldString(fields, 'baslik'),
    ]) ?? '';
    if (baslik.trim().isEmpty) continue;

    final kurum = firstNonBlank([
      fieldString(fields, 'kurum'),
      fieldString(fields, 'kurulus'),
      fieldString(fields, 'kampanyaKurumu'),
    ]) ?? '';

    final aciklama = fieldString(fields, 'aciklama') ?? '';
    final link = firstNonBlank([
      fieldString(fields, 'link'),
      fieldString(fields, 'detayLink'),
      fieldString(fields, 'detaylink'),
    ]) ?? '';

    final tarih = firstNonBlank([
      fieldTimestamp(fields, 'tarih'),
      fieldTimestamp(fields, 'eklenmeTarihi'),
      doc['updateTime']?.toString(),
      doc['createTime']?.toString(),
    ]) ?? '';

    final etiketler = tagsFromFields(fields, kurum);

    kampanyalar.add({
      'id': id,
      'baslik': baslik,
      'kurum': kurum,
      'aciklama': aciklama,
      'link': link,
      'tarih': tarih,
      'etiketler': etiketler,
    });
  }

  kampanyalar.sort((a, b) {
    final ta = DateTime.tryParse(a['tarih'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    final tb = DateTime.tryParse(b['tarih'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  });

  final output = {
    'version': '1',
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'kampanyalar': kampanyalar,
  };

  final encoder = JsonEncoder.withIndent('  ');
  File(outputPath).writeAsStringSync('${encoder.convert(output)}\n');
  stdout.writeln('Exported ${kampanyalar.length} campaigns -> $outputPath');
}
