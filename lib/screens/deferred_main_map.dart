import 'dart:async';

import 'package:flutter/material.dart';

import '../data/firebase_rota_repository.dart';
import '../navigation/main_map_nav_bridge.dart';
import 'main_map_screen.dart' deferred as map_lib;

/// İlk karede harita kütüphanesini derlemez; ana sayfa hemen boyanır.
class DeferredMainMap extends StatefulWidget {
  const DeferredMainMap({
    super.key,
    required this.repository,
    required this.navBridge,
  });

  final FirebaseRotaRepository repository;
  final MainMapNavBridge navBridge;

  @override
  State<DeferredMainMap> createState() => _DeferredMainMapState();
}

class _DeferredMainMapState extends State<DeferredMainMap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadMap());
    });
  }

  Future<void> _loadMap() async {
    await map_lib.loadLibrary();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.expand();
    return map_lib.MainMapScreen(
      repository: widget.repository,
      navBridge: widget.navBridge,
    );
  }
}
