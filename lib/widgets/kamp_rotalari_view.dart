import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/kamp_repository.dart';
import '../theme/app_colors.dart';
import '../utils/maps_launch.dart';
import 'rotalink_tile_layer.dart';

class KampRotalariBody extends StatefulWidget {
  const KampRotalariBody({super.key, required this.iller});

  final Set<String> iller;

  @override
  State<KampRotalariBody> createState() => _KampRotalariBodyState();
}

class _KampRotalariBodyState extends State<KampRotalariBody> {
  final _sorgu = TextEditingController();
  var _filtre = const KampFiltre();
  var _harita = false;

  @override
  void dispose() {
    _sorgu.dispose();
    super.dispose();
  }

  void _chip(KampFiltre next) => setState(() => _filtre = next);

  @override
  Widget build(BuildContext context) {
    final kaynak = KampRepository.instance.forIller(widget.iller);
    final goster = kampFiltrele(kaynak, _filtre);
    final yuklendi = KampRepository.instance.items.value.isNotEmpty || kaynak.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: TextField(
            controller: _sorgu,
            onChanged: (v) => setState(() => _filtre = KampFiltre(
                  sorgu: v,
                  cadir: _filtre.cadir,
                  karavan: _filtre.karavan,
                  ucretsiz: _filtre.ucretsiz,
                  ucretli: _filtre.ucretli,
                  elektrik: _filtre.elektrik,
                  dus: _filtre.dus,
                  tuvalet: _filtre.tuvalet,
                )),
            decoration: InputDecoration(
              hintText: 'İl veya kamp alanı ara',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: const Color(0xFFF4F7F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _f('Çadır', _filtre.cadir, (v) => _chip(_kopya(cadir: v))),
              _f('Karavan', _filtre.karavan, (v) => _chip(_kopya(karavan: v))),
              _f('Ücretsiz', _filtre.ucretsiz, (v) => _chip(_kopya(ucretsiz: v))),
              _f('Ücretli', _filtre.ucretli, (v) => _chip(_kopya(ucretli: v))),
              _f('Elektrik', _filtre.elektrik, (v) => _chip(_kopya(elektrik: v))),
              _f('Duş', _filtre.dus, (v) => _chip(_kopya(dus: v))),
              _f('Tuvalet', _filtre.tuvalet, (v) => _chip(_kopya(tuvalet: v))),
              const SizedBox(width: 8),
              IconButton(
                tooltip: _harita ? 'Liste' : 'Harita',
                onPressed: goster.isEmpty ? null : () => setState(() => _harita = !_harita),
                icon: Icon(_harita ? Icons.view_list_rounded : Icons.map_outlined, size: 20),
              ),
            ],
          ),
        ),
        Expanded(
          child: goster.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      yuklendi
                          ? 'Bu aramada kamp alanı yok. Bilinmeyen yer eklenmez.'
                          : 'Kamp listesi henüz inmedi. İnternet bağlantınızı kontrol edin.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF6B7C82), height: 1.4),
                    ),
                  ),
                )
              : _harita
                  ? _KampHarita(items: goster)
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: goster.length + 1,
                      separatorBuilder: (_, i) =>
                          i == goster.length - 1 ? const SizedBox.shrink() : const Divider(height: 1),
                      itemBuilder: (context, i) {
                        if (i == goster.length) return const _Atif();
                        return _KampSatir(item: goster[i]);
                      },
                    ),
        ),
      ],
    );
  }

  KampFiltre _kopya({
    bool? cadir,
    bool? karavan,
    bool? ucretsiz,
    bool? ucretli,
    bool? elektrik,
    bool? dus,
    bool? tuvalet,
  }) {
    return KampFiltre(
      sorgu: _filtre.sorgu,
      cadir: cadir ?? _filtre.cadir,
      karavan: karavan ?? _filtre.karavan,
      ucretsiz: ucretsiz ?? _filtre.ucretsiz,
      ucretli: ucretli ?? _filtre.ucretli,
      elektrik: elektrik ?? _filtre.elektrik,
      dus: dus ?? _filtre.dus,
      tuvalet: tuvalet ?? _filtre.tuvalet,
    );
  }

  Widget _f(String label, bool secili, ValueChanged<bool> on) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        selected: secili,
        onSelected: on,
        visualDensity: VisualDensity.compact,
        selectedColor: AppColors.primary.withValues(alpha: 0.16),
        checkmarkColor: AppColors.primary,
      ),
    );
  }
}

class _Atif extends StatelessWidget {
  const _Atif();

  @override
  Widget build(BuildContext context) {
    final metin = KampRepository.instance.atif.isEmpty
        ? 'Konum verisi © OpenStreetMap katkıları (ODbL). Resmî fiyat değildir.'
        : '${KampRepository.instance.atif}. Resmî fiyat değildir.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(metin, style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11.5, height: 1.35)),
    );
  }
}

class _KampSatir extends StatelessWidget {
  const _KampSatir({required this.item});

  final KampAlani item;

  @override
  Widget build(BuildContext context) {
    final yer = [item.il, if (item.ilce != null) item.ilce].join(' · ');
    return ListTile(
      onTap: () => unawaited(showKampDetay(context, item)),
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        child: Icon(
          item.kampTuru == 'karavan' ? Icons.rv_hookup_rounded : Icons.park_rounded,
          color: AppColors.primary,
          size: 20,
        ),
      ),
      title: Text(item.ad, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      subtitle: Text(
        [yer, kampTuruEtiket(item.kampTuru), ?_ucret(item)].join(' · '),
        style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7C82)),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Color(0xFFB0BEC5)),
    );
  }
}

String? _ucret(KampAlani k) {
  if (k.resmiFiyat) {
    final birim = k.fiyatBirim == null ? '' : ' / ${k.fiyatBirim}';
    return '${k.fiyat!.toStringAsFixed(k.fiyat! == k.fiyat!.roundToDouble() ? 0 : 2)} ₺$birim';
  }
  if (k.ucret == 'ucretsiz') return 'Ücretsiz';
  if (k.ucret == 'ucretli') return 'Ücretli';
  return null;
}

class _KampHarita extends StatelessWidget {
  const _KampHarita({required this.items});

  final List<KampAlani> items;

  @override
  Widget build(BuildContext context) {
    final ilk = LatLng(items.first.enlem, items.first.boylam);
    return FlutterMap(
      options: MapOptions(initialCenter: ilk, initialZoom: items.length == 1 ? 12 : 6),
      children: [
        const RotalinkTileLayer(),
        MarkerLayer(
          markers: [
            for (final k in items)
              Marker(
                point: LatLng(k.enlem, k.boylam),
                width: 36,
                height: 36,
                child: GestureDetector(
                  onTap: () => unawaited(showKampDetay(context, k)),
                  child: const Icon(Icons.place_rounded, color: AppColors.primary, size: 32),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Future<void> showKampDetay(BuildContext context, KampAlani k) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(k.ad, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            '${k.il}${k.ilce == null ? '' : ' / ${k.ilce}'} · ${kampTuruEtiket(k.kampTuru)}',
            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
          ),
          if (k.adres != null) ...[
            const SizedBox(height: 8),
            Text(k.adres!, style: const TextStyle(color: Color(0xFF546E7A), height: 1.35)),
          ],
          const SizedBox(height: 14),
          ..._satirlar([
            ('Ücret', _ucret(k)),
            ('Çadır', _evet(k.cadir)),
            ('Karavan', _evet(k.karavan)),
            ('Motokaravan', _evet(k.motokaravan)),
            ('Elektrik', _evet(k.elektrik)),
            ('Tuvalet', _evet(k.tuvalet)),
            ('Duş', _evet(k.dus)),
            ('İçme suyu', _evet(k.icmeSuyu)),
            ('Atık boşaltma', _evet(k.atik)),
            ('Wi-Fi', _evet(k.wifi)),
            ('Otopark', _evet(k.otopark)),
            ('Denize yakın', _evet(k.denizeYakin)),
            ('Telefon', k.telefon),
            ('Rezervasyon', k.rezervasyon),
          ]),
          const SizedBox(height: 8),
          ..._satirlar([('Son kontrol', _tarih(k.sonKontrol))]),
          _satir('Doğrulama', k.dogrulama == 'resmi' ? 'Resmî kaynak' : 'Açık veri'),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(openInNativeMaps(
                ctx,
                query: '${k.ad} ${k.il}',
                latitude: k.enlem,
                longitude: k.boylam,
              )),
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: const Text('Yol tarifi'),
            ),
          ),
          if (k.kaynakUrl != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => unawaited(_ac(k.kaynakUrl!)),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Kaynağı görüntüle'),
              ),
            ),
          if (k.web != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  final u = Uri.tryParse(k.web!);
                  if (u != null) unawaited(_ac(u));
                },
                icon: const Icon(Icons.language_rounded, size: 18),
                label: const Text('Resmî site'),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            k.atif.isEmpty ? '© OpenStreetMap katkıları (ODbL)' : k.atif,
            style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11.5, height: 1.35),
          ),
        ],
      ),
    ),
  );
}

Widget _satir(String ad, String deger) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(ad, style: const TextStyle(color: Color(0xFF78909C), fontSize: 13))),
        Expanded(child: Text(deger, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}

/// Değeri bilinmeyen satır gösterilmez.
List<Widget> _satirlar(List<(String, String?)> rows) => [
      for (final (ad, deger) in rows)
        if (deger != null && deger.trim().isNotEmpty) _satir(ad, deger),
    ];

String? _evet(bool? v) {
  if (v == true) return 'Var';
  if (v == false) return 'Yok';
  return null;
}

String? _tarih(DateTime? d) {
  if (d == null) return null;
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

Future<void> _ac(Uri u) async {
  if (u.scheme != 'https' && u.scheme != 'http') return;
  try {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  } catch (_) {}
}
