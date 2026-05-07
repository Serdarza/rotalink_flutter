import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/review_repository.dart';
import '../theme/app_colors.dart';

// ── Argo Filtresi ─────────────────────────────────────────────────────────────

const _kArgoBlacklist = {
  'orospu', 'siktir', 'amk', 'piç', 'oç', 'göt', 'yarrak', 'amına',
  'ibne', 'kahpe', 'pezevenk', 'pezevek', 'sikik', 'oğlancı',
  'gerizekalı', 'dangalak', 'aptal', 'salak', 'mal', 'götü',
};

bool _containsBlacklisted(String text) {
  final lower = text.toLowerCase();
  return _kArgoBlacklist.any(lower.contains);
}

// ── Renk Sabitleri ────────────────────────────────────────────────────────────

const _kTeal = AppColors.primary;
const _kStarGold = Color(0xFFFFC107);
const _kStarEmpty = Color(0xFFBDBDBD);
const _kDeleteRed = Color(0xFFE53935);
const _kShimmerLight = Color(0xFFEEEEEE);
const _kShimmerBright = Color(0xFFF9F9F9);

// ── userId yardımcısı ─────────────────────────────────────────────────────────

Future<String> _getOrCreateUserId() async {
  final prefs = await SharedPreferences.getInstance();
  const key = 'rotalink_user_id';
  var id = prefs.getString(key);
  if (id == null || id.isEmpty) {
    id = DateTime.now().millisecondsSinceEpoch.toString() +
        UniqueKey().toString();
    await prefs.setString(key, id);
  }
  return id;
}

// ── YorumScreen ───────────────────────────────────────────────────────────────

class YorumScreen extends StatefulWidget {
  const YorumScreen({
    super.key,
    required this.facilityId,
    required this.facilityName,
  });

  final String facilityId;
  final String facilityName;

  @override
  State<YorumScreen> createState() => _YorumScreenState();
}

class _YorumScreenState extends State<YorumScreen> {
  String _userId = '';
  List<Review>? _reviews;
  StreamSubscription<List<Review>>? _reviewSub;

  int _selectedRating = 0;
  final _textController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMsg;

  final _snackbarKey = GlobalKey<ScaffoldMessengerState>();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _userId = await _getOrCreateUserId();
    _reviewSub = ReviewRepository.instance
        .getReviewsStream(widget.facilityId)
        .listen((list) {
      if (mounted) setState(() => _reviews = list);
    }, onError: (_) {
      if (mounted) setState(() => _reviews = []);
    });
  }

  @override
  void dispose() {
    _reviewSub?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitReview() async {
    if (_selectedRating == 0) {
      setState(() => _errorMsg = 'Lütfen bir puan seçin.');
      return;
    }
    final trimmed = _textController.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _errorMsg = 'Lütfen bir yorum yazın.');
      return;
    }
    if (_containsBlacklisted(trimmed)) {
      setState(() =>
          _errorMsg = 'Lütfen topluluk kurallarına uygun bir dil kullanın.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMsg = null;
    });
    try {
      await ReviewRepository.instance.addReview(
        facilityId: widget.facilityId,
        review: Review(
          id: '',
          userId: _userId,
          userName: '',
          rating: _selectedRating,
          text: trimmed,
          createdAt: 0,
          likes: const {},
        ),
      );
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _selectedRating = 0;
          _textController.clear();
        });
        FocusScope.of(context).unfocus();
        _snackbarKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Yorumunuz eklendi. Teşekkürler!')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMsg = 'Yorum gönderilemedi. Tekrar deneyin.';
        });
      }
    }
  }

  void _deleteReview(Review r) async {
    try {
      await ReviewRepository.instance.deleteReview(
        facilityId: widget.facilityId,
        reviewId: r.id,
      );
      if (mounted) {
        _snackbarKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Yorum silindi.')),
        );
      }
    } catch (_) {
      if (mounted) {
        _snackbarKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Silinemedi. Tekrar deneyin.')),
        );
      }
    }
  }

  void _toggleLike(Review review) {
    final alreadyLiked = review.likes.containsKey(_userId);
    ReviewRepository.instance
        .toggleLike(
          facilityId: widget.facilityId,
          reviewId: review.id,
          userId: _userId,
          alreadyLiked: alreadyLiked,
        )
        .catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _snackbarKey,
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4F5),
        appBar: AppBar(
          backgroundColor: _kTeal,
          foregroundColor: Colors.white,
          title: Text(
            widget.facilityName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          elevation: 0,
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            controller: _scrollController,
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
            children: [
              _RatingInputCard(
                selectedRating: _selectedRating,
                textController: _textController,
                isSubmitting: _isSubmitting,
                errorMsg: _errorMsg,
                onRatingChange: (v) =>
                    setState(() {
                      _selectedRating = v;
                      _errorMsg = null;
                    }),
                onTextChange: (_) =>
                    setState(() => _errorMsg = null),
                onSubmit: _submitReview,
              ),
              const SizedBox(height: 16),
              _ReviewsHeader(reviews: _reviews),
              const SizedBox(height: 12),
              if (_reviews == null)
                ...[for (int i = 0; i < 3; i++) const _ShimmerCard()]
              else if (_reviews!.isEmpty)
                const _EmptyReviewsMessage()
              else
                ..._reviews!.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ReviewCard(
                        review: r,
                        currentUserId: _userId,
                        onDeleteTap: () => _confirmDelete(r),
                        onLikeTap: () => _toggleLike(r),
                      ),
                    )),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Review r) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Yorumu Sil',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: const Text(
            'Bu yorumunuzu kalıcı olarak silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteReview(r);
            },
            child: const Text('Evet, Sil',
                style: TextStyle(
                    color: _kDeleteRed, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Yorum Giriş Kartı ─────────────────────────────────────────────────────────

class _RatingInputCard extends StatelessWidget {
  const _RatingInputCard({
    required this.selectedRating,
    required this.textController,
    required this.isSubmitting,
    required this.errorMsg,
    required this.onRatingChange,
    required this.onTextChange,
    required this.onSubmit,
  });

  final int selectedRating;
  final TextEditingController textController;
  final bool isSubmitting;
  final String? errorMsg;
  final ValueChanged<int> onRatingChange;
  final ValueChanged<String> onTextChange;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Yorum & Puan Ekle',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _kTeal),
            ),
            const SizedBox(height: 14),
            // Yıldız seçici
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                final star = i + 1;
                return GestureDetector(
                  onTap: () => onRatingChange(star),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.star,
                      size: 36,
                      color: star <= selectedRating ? _kStarGold : _kStarEmpty,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              onChanged: onTextChange,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Deneyiminizi paylaşın...',
                hintStyle:
                    TextStyle(color: Colors.grey.shade500),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kTeal, width: 2),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onSubmit(),
            ),
            if (errorMsg != null) ...[
              const SizedBox(height: 6),
              Text(errorMsg!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: isSubmitting ? null : onSubmit,
              icon: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send, size: 18),
              label: const Text('Gönder',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kTeal,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Yorumlar Başlığı ──────────────────────────────────────────────────────────

class _ReviewsHeader extends StatelessWidget {
  const _ReviewsHeader({required this.reviews});

  final List<Review>? reviews;

  @override
  Widget build(BuildContext context) {
    final list = reviews;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Son 1 Yılın Yorumları',
          style:
              TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        if (list != null && list.isNotEmpty)
          Row(children: [
            const Icon(Icons.star, size: 16, color: _kStarGold),
            const SizedBox(width: 3),
            Text(
              list.map((r) => r.rating).reduce((a, b) => a + b) /
                          list.length >=
                      0
                  ? (list.map((r) => r.rating).reduce((a, b) => a + b) /
                          list.length)
                      .toStringAsFixed(1)
                  : '0.0',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold),
            ),
            Text(
              ' | ${list.length} Yorum',
              style: const TextStyle(
                  fontSize: 13, color: Colors.grey),
            ),
          ]),
      ],
    );
  }
}

// ── Yorum Kartı ───────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.currentUserId,
    required this.onDeleteTap,
    required this.onLikeTap,
  });

  final Review review;
  final String currentUserId;
  final VoidCallback onDeleteTap;
  final VoidCallback onLikeTap;

  @override
  Widget build(BuildContext context) {
    final isLiked = review.likes.containsKey(currentUserId);
    final likeCount = review.likes.length;
    final isOwner = review.userId == currentUserId;
    final dateStr = review.createdAt > 0
        ? DateFormat('dd.MM.yyyy HH:mm', 'tr').format(
            DateTime.fromMillisecondsSinceEpoch(review.createdAt))
        : '';

    return Card(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 19,
                  backgroundColor: _kTeal,
                  child: const Icon(Icons.person,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ...List.generate(5, (i) {
                            final star = i + 1;
                            return Icon(
                              Icons.star,
                              size: 14,
                              color: star <= review.rating
                                  ? _kStarGold
                                  : _kStarEmpty,
                            );
                          }),
                          if (dateStr.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(dateStr,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (isOwner)
                  GestureDetector(
                    onTap: onDeleteTap,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.delete_outline,
                          color: _kDeleteRed, size: 22),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 0.5),
            const SizedBox(height: 8),
            Text(
              review.text,
              style:
                  const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: onLikeTap,
                  child: Icon(
                    Icons.thumb_up_outlined,
                    size: 22,
                    color: isLiked ? _kTeal : Colors.grey,
                  ),
                ),
                const SizedBox(width: 6),
                if (likeCount > 0)
                  Text(
                    '$likeCount kişi faydalı buldu',
                    style: TextStyle(
                      fontSize: 12,
                      color: isLiked ? _kTeal : Colors.grey,
                      fontWeight: isLiked
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  )
                else
                  const Text('Faydalı mıydı?',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Boş Durum ─────────────────────────────────────────────────────────────────

class _EmptyReviewsMessage extends StatelessWidget {
  const _EmptyReviewsMessage();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.blueGrey.shade100,
              child: Icon(Icons.chat_bubble_outline,
                  size: 40, color: Colors.blueGrey.shade400),
            ),
            const SizedBox(height: 16),
            const Text(
              'Henüz hiç yorum yapılmamış',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Bu tesisle ilgili deneyimini paylaş,\ndiğer kullanıcılara yardımcı ol.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, color: _kStarGold, size: 16),
                SizedBox(width: 4),
                Text(
                  'İlk yorumu sen yaz!',
                  style: TextStyle(
                      color: _kStarGold,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shimmer Yükleme Kartı ─────────────────────────────────────────────────────

class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard();

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) {
        final shimmer = LinearGradient(
          colors: const [_kShimmerLight, _kShimmerBright, _kShimmerLight],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment(-1 + _anim.value * 2, 0),
          end: Alignment(1 + _anim.value * 2, 0),
        );
        return Card(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: shimmer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          height: 12,
                          width: 120,
                          decoration: BoxDecoration(
                              gradient: shimmer,
                              borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 6),
                      Container(
                          height: 10,
                          width: 80,
                          decoration: BoxDecoration(
                              gradient: shimmer,
                              borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                  height: 14,
                  decoration: BoxDecoration(
                      gradient: shimmer,
                      borderRadius: BorderRadius.circular(6))),
              const SizedBox(height: 6),
              Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                      gradient: shimmer,
                      borderRadius: BorderRadius.circular(6))),
            ]),
          ),
        );
      },
    );
  }
}
