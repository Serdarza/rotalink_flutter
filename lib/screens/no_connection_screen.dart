import 'dart:async';

import 'package:flutter/material.dart';

import '../services/network_service.dart';
import '../theme/app_colors.dart';

/// Cihazda internet bağlantısı olmadığında gösterilen tam ekran sayfa.
///
/// İki yoldan kapanır:
/// 1. Kullanıcı "Tekrar Dene" butonuna basar ve bağlantı varsa [onConnected] tetiklenir.
/// 2. Bağlantı otomatik olarak geri gelirse (connectivity stream) [onConnected] tetiklenir.
class NoConnectionScreen extends StatefulWidget {
  const NoConnectionScreen({super.key, required this.onConnected});

  final VoidCallback onConnected;

  @override
  State<NoConnectionScreen> createState() => _NoConnectionScreenState();
}

class _NoConnectionScreenState extends State<NoConnectionScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  StreamSubscription<bool>? _sub;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    // Bağlantı otomatik gelirse sayfayı kapat.
    _sub = NetworkService.instance.onConnectivityChanged.listen((connected) {
      if (connected && mounted) _proceed();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final connected = await NetworkService.instance.isConnected();
    if (!mounted) return;
    if (connected) {
      _proceed();
    } else {
      setState(() => _retrying = false);
    }
  }

  void _proceed() {
    _sub?.cancel();
    widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ─── İkon ──────────────────────────────────────────────────────
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.08),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 52,
                    color: AppColors.primary,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ─── Başlık ────────────────────────────────────────────────────
              const Text(
                'Bağlantı Yok',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: 0.2,
                ),
              ),

              const SizedBox(height: 12),

              // ─── Açıklama ──────────────────────────────────────────────────
              Text(
                'RotaLink\'e bağlanılamıyor.\nLütfen internet bağlantınızı\nkontrol edip tekrar deneyin.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: Colors.grey.shade600,
                  height: 1.55,
                ),
              ),

              const SizedBox(height: 48),

              // ─── Tekrar Dene butonu ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _retrying ? null : _retry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: _retrying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                  label: Text(
                    _retrying ? 'Bağlanıyor...' : 'Tekrar Dene',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
