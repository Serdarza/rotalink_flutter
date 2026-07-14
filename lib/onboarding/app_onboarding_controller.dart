import 'dart:async';

import 'package:flutter/material.dart';

import '../kami/kami_overlay.dart';
import 'onboarding_prefs.dart';

enum OnboardingTarget {
  menu,
  searchChrome,
  weather,
  navSearch,
  navDiscover,
  navRoute,
  navFavorites,
  kami,
  emergency,
}

enum OnboardingTooltipAlign { above, below, left, center }

class OnboardingStep {
  const OnboardingStep({
    required this.title,
    required this.body,
    this.icon,
    this.target,
    this.align = OnboardingTooltipAlign.below,
    this.ensureHome = false,
  });

  final String title;
  final String body;
  final IconData? icon;
  final OnboardingTarget? target;
  final OnboardingTooltipAlign align;
  final bool ensureHome;
}

/// İlk açılış adım adım tur kontrolcüsü.
class AppOnboardingController extends ChangeNotifier {
  AppOnboardingController({required VoidCallback onEnsureHome})
      : _onEnsureHome = onEnsureHome;

  final VoidCallback _onEnsureHome;
  final Map<OnboardingTarget, GlobalKey> _keys = {};

  bool active = false;
  int _index = 0;

  static const steps = <OnboardingStep>[
    OnboardingStep(
      title: 'Rotalink\'e hoş geldiniz',
      body:
          'Kamu misafirhaneleri, rota planlama, kampanyalar ve yapay zekâ asistanı tek uygulamada. Kısa bir tur ile en önemli yerlere bakalım.',
      icon: Icons.waving_hand_rounded,
      align: OnboardingTooltipAlign.center,
    ),
    OnboardingStep(
      title: 'Menü',
      body:
          'Sol üst menüden hava durumu detayı, resmi tatiller, öneri gönderme, web sitemiz ve sosyal medya hesaplarımıza ulaşabilirsiniz.',
      icon: Icons.menu_rounded,
      target: OnboardingTarget.menu,
      align: OnboardingTooltipAlign.below,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Arama',
      body:
          'Şehir veya misafirhane arayın. Sesli arama, il önerileri ve tesis tipi filtreleri ile sonuçları daraltın; haritada anında görün.',
      icon: Icons.search_rounded,
      target: OnboardingTarget.searchChrome,
      align: OnboardingTooltipAlign.below,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Hava durumu',
      body:
          'Sağ üstte anlık sıcaklık ve hava durumu. Konumunuz, haritadaki il veya varsayılan şehre göre güncellenir; dokunarak detaylı tahmin açılır.',
      icon: Icons.wb_sunny_rounded,
      target: OnboardingTarget.weather,
      align: OnboardingTooltipAlign.below,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'KAMİ asistan',
      body:
          'Yapay zekâ seyahat asistanınız. Örneğin «Ankara\'ya gidiyorum, misafirhane öner» diyerek rota ve konaklama önerisi alabilirsiniz.',
      icon: Icons.smart_toy_rounded,
      target: OnboardingTarget.kami,
      align: OnboardingTooltipAlign.left,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Acil durum',
      body:
          'Kırmızı ACİL düğmesi: SOS, en yakın hastane ve acil yardım numaraları. Yolda güvende kalmanız için her zaman elinizin altında.',
      icon: Icons.emergency_rounded,
      target: OnboardingTarget.emergency,
      align: OnboardingTooltipAlign.left,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Ara',
      body:
          'Alt menüdeki Ara ile arama çubuğuna tek dokunuşla geçersiniz; klavye açılır ve hemen yazmaya başlayabilirsiniz.',
      icon: Icons.search_rounded,
      target: OnboardingTarget.navSearch,
      align: OnboardingTooltipAlign.above,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Keşfet',
      body:
          'Personel indirimleri, kampanyalar ve fırsatlar burada. İl veya kurum adıyla arayıp detaylara ve bağlantılara gidebilirsiniz.',
      icon: Icons.card_giftcard_rounded,
      target: OnboardingTarget.navDiscover,
      align: OnboardingTooltipAlign.above,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Rota planla',
      body:
          'Çok duraklı yolculuk planlayın. Her şehir için misafirhane, gezi ve yemek önerileri; rotayı haritada görüntüleyip kaydedin.',
      icon: Icons.alt_route_rounded,
      target: OnboardingTarget.navRoute,
      align: OnboardingTooltipAlign.above,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Favorilerim',
      body:
          'Beğendiğiniz tesisleri kalp ile kaydedin. Favoriler sekmesinde listeyi açar, haritada hepsini bir arada görürsünüz.',
      icon: Icons.favorite_rounded,
      target: OnboardingTarget.navFavorites,
      align: OnboardingTooltipAlign.above,
      ensureHome: true,
    ),
    OnboardingStep(
      title: 'Hazırsınız',
      body:
          'Artık keşfetmeye başlayabilirsiniz. İyi yolculuklar! Menüden ve alt çubuktan istediğiniz zaman bu özelliklere dönebilirsiniz.',
      icon: Icons.check_circle_rounded,
      align: OnboardingTooltipAlign.center,
    ),
  ];

  OnboardingStep get currentStep => steps[_index];
  int get stepIndex => _index;
  int get stepCount => steps.length;
  bool get isLastStep => _index >= steps.length - 1;

  GlobalKey targetKey(OnboardingTarget target) =>
      _keys.putIfAbsent(target, GlobalKey.new);

  Rect? targetRectIn(OnboardingTarget target) {
    final key = _keys[target];
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  void start() {
    KamiSessionState.bubbleConsumed = true;
    active = true;
    _index = 0;
    _onEnsureHome();
    notifyListeners();
  }

  Future<void> next() async {
    if (isLastStep) {
      await complete();
      return;
    }
    _index++;
    if (currentStep.ensureHome) {
      _onEnsureHome();
    }
    notifyListeners();
  }

  Future<void> skip() => complete();

  Future<void> complete() async {
    active = false;
    await OnboardingPrefs.markCompleted();
    notifyListeners();
  }
}
