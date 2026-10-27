import 'package:flutter/material.dart';
import '../models/misafirhane.dart';
import '../data/facility_address_repository.dart';
import '../data/facility_price_repository.dart';
import '../utils/il_ilce.dart';
import 'search_results_ui.dart';

/// Nearby and search lists share exactly the same facility card presentation.
class NearbyGuesthouseCard extends StatelessWidget {
  const NearbyGuesthouseCard({
    super.key,
    required this.facility,
    required this.distanceKm,
    required this.onTap,
  });

  final Misafirhane facility;
  final double? distanceKm;
  final VoidCallback onTap;

  static Misafirhane displayFacility(Misafirhane facility) {
    final resolved = FacilityAddressRepository.instance.resolveFacility(
      facility,
    );
    final district = IlIlce.inferIlce(
      resolved.il,
      ilce: resolved.ilce,
      adres: resolved.adres,
    );
    return district == resolved.ilce
        ? resolved
        : resolved.copyWithAddress(ilce: district);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = displayFacility(facility);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SearchFacilityResultCard(
        name: resolved.isim,
        location: IlIlce.label(resolved.il, resolved.ilce),
        hasPrice:
            FacilityPriceRepository.instance
                .lookup(facility.il, facility.isim)
                ?.hasFiyatBilgisi ==
            true,
        locationPermissionGranted: distanceKm != null,
        userLocation: null,
        facilityPoint: null,
        distanceKm: distanceKm,
        onTap: onTap,
      ),
    );
  }
}
