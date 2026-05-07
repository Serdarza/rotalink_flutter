import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/campaign.dart';

/// Kotlin [DiscoverActivity] Firestore sorgusu.
class CampaignRepository {
  CampaignRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String collectionKampanyalar = 'KAMPANYALAR';

  Stream<List<Campaign>> watchCampaignsOrdered() {
    return _db
        .collection(collectionKampanyalar)
        .orderBy('tarih', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map(Campaign.fromFirestore)
          .where((c) => c.title.trim().isNotEmpty)
          .toList();
    });
  }
}
