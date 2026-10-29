import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/store_links.dart';
import '../data/favorites_repository.dart';
import '../map_location_state.dart';
import '../models/misafirhane.dart';
import '../navigator_keys.dart';
import '../screens/yorum_screen.dart';
import '../services/review_repository.dart';
import '../utils/facility_phone_dialer.dart';
import '../utils/maps_launch.dart';
import 'facility_detail_card.dart';

/// Tesis kartı. Geri, kartı açan ekrana döner.
class KonumFacilityPage extends StatefulWidget {
  const KonumFacilityPage({super.key, required this.facility});

  final Misafirhane facility;

  @override
  State<KonumFacilityPage> createState() => _KonumFacilityPageState();
}

class _KonumFacilityPageState extends State<KonumFacilityPage> {
  final _favorites = FavoritesRepository();
  final _location = MapLocationState();
  var _favorite = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorite());
  }

  Future<void> _loadFavorite() async {
    final saved = await _favorites.load();
    if (!mounted) return;
    setState(
      () => _favorite = saved.any(
        (item) => item.sameFavoriteIdentity(widget.facility),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final facility = widget.facility;
    return FacilityDetailCard(
      misafirhane: facility,
      mapLocationState: _location,
      isFavorite: _favorite,
      onBack: () {
        final shell = rotalinkShellBodyNavigatorKey.currentState;
        if (shell != null && shell.canPop()) {
          shell.pop();
          return;
        }
        Navigator.of(context).maybePop();
      },
      onCall: () => FacilityPhoneDialer.open(context, facility),
      onShare: () {
        final phone = facility.telefonNumaralari.join(' / ');
        unawaited(
          Share.share(
            StoreLinks.shareMessage(facility.isim, [
              if (phone.isNotEmpty) 'Telefon: $phone',
            ]),
          ),
        );
      },
      onFavorite: () async {
        await _favorites.toggle(facility);
        await _loadFavorite();
      },
      onInspect: () => openMapSearch(context, facility.il, facility.isim),
      onReview: () => pushOnShellNavigator<void>(
        MaterialPageRoute<void>(
          builder: (_) => YorumScreen(
            facilityId: ReviewRepository.sanitizeFacilityId(
              facility.stableFacilityId,
            ),
            facilityName: facility.isim,
          ),
        ),
      ),
      onShowOnMap: () => openMapSearch(context, facility.il, facility.isim),
      onRequestLocation: () async {},
    );
  }
}
