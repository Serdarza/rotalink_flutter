import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

// ── Veri Modelleri ────────────────────────────────────────────────────────────

class Review {
  const Review({
    required this.id,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.text,
    required this.createdAt,
    required this.likes,
  });

  final String id;
  final String userId;
  final String userName;
  final int rating;
  final String text;
  final int createdAt;
  final Map<String, bool> likes;

  Review copyWith({
    String? id,
    String? userId,
    String? userName,
    int? rating,
    String? text,
    int? createdAt,
    Map<String, bool>? likes,
  }) {
    return Review(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      rating: rating ?? this.rating,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      likes: likes ?? this.likes,
    );
  }
}

class RatingSummary {
  const RatingSummary({this.averageRating = 0.0, this.reviewCount = 0});

  final double averageRating;
  final int reviewCount;
}

// ── Repository ────────────────────────────────────────────────────────────────
//
// Firestore koleksiyon yapısı:
//   misafirhaneReviews/{facilityId}/yorumlar/{docId}
//
//   misafirhaneRatings/{facilityId}
//     → averageRating (double), reviewCount (int)

class ReviewRepository {
  ReviewRepository._();
  static final ReviewRepository instance = ReviewRepository._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _reviewsCol(String facilityId) =>
      _db
          .collection('misafirhaneReviews')
          .doc(facilityId)
          .collection('yorumlar');

  DocumentReference<Map<String, dynamic>> _ratingsDoc(String facilityId) =>
      _db.collection('misafirhaneRatings').doc(facilityId);

  /// Firebase key-uyumsuz karakterleri temizler.
  static String sanitizeFacilityId(String raw) =>
      raw.replaceAll(RegExp(r'[^\w\sğüşıöçĞÜŞİÖÇ]'), '_').trim();

  /// Tesisin yorumlarını gerçek zamanlı Stream olarak döner.
  /// Son 1 yıla ait en fazla 150 yorum, en çok beğenilen üstte.
  Stream<List<Review>> getReviewsStream(String facilityId) {
    final oneYearAgoMs =
        DateTime.now().millisecondsSinceEpoch - 365 * 24 * 60 * 60 * 1000;

    return _reviewsCol(facilityId)
        .orderBy('createdAt', descending: true)
        .limit(150)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) {
            final data = doc.data();
            final createdAt = (data['createdAt'] as num?)?.toInt() ?? 0;
            if (createdAt < oneYearAgoMs) return null;
            final rawLikes = data['likes'];
            final likes = <String, bool>{};
            if (rawLikes is Map) {
              rawLikes.forEach((k, v) {
                if (v == true) likes[k.toString()] = true;
              });
            }
            return Review(
              id: doc.id,
              userId: (data['userId'] as String?) ?? '',
              userName: (data['userName'] as String?) ?? '',
              rating: (data['rating'] as num?)?.toInt() ?? 0,
              text: (data['text'] as String?) ?? '',
              createdAt: createdAt,
              likes: likes,
            );
          })
          .whereType<Review>()
          .toList()
        ..sort((a, b) => b.likes.length.compareTo(a.likes.length));
      return list;
    });
  }

  /// Yeni yorum ekler.
  Future<void> addReview({
    required String facilityId,
    required Review review,
  }) async {
    final data = {
      'userId': review.userId,
      'userName': review.userName,
      'rating': review.rating,
      'text': review.text,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    await _reviewsCol(facilityId).add(data);
    unawaited(_refreshAggregate(facilityId));
  }

  /// Beğeni ekler veya kaldırır.
  Future<void> toggleLike({
    required String facilityId,
    required String reviewId,
    required String userId,
    required bool alreadyLiked,
  }) async {
    final docRef = _reviewsCol(facilityId).doc(reviewId);
    if (alreadyLiked) {
      await docRef.update({'likes.$userId': FieldValue.delete()});
    } else {
      await docRef.update({'likes.$userId': true});
    }
  }

  /// Kullanıcının kendi yorumunu siler.
  Future<void> deleteReview({
    required String facilityId,
    required String reviewId,
  }) async {
    await _reviewsCol(facilityId).doc(reviewId).delete();
    unawaited(_refreshAggregate(facilityId));
  }

  Future<void> _refreshAggregate(String facilityId) async {
    final snapshot = await _reviewsCol(facilityId).get();
    var total = 0.0;
    var count = 0;
    for (final doc in snapshot.docs) {
      final r = (doc.data()['rating'] as num?)?.toInt() ?? 0;
      total += r;
      count++;
    }
    final avg = count > 0 ? total / count : 0.0;
    await _ratingsDoc(facilityId).set({
      'averageRating': avg,
      'reviewCount': count,
    });
  }
}

