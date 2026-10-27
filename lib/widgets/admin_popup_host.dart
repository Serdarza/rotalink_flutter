import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/admin_popup.dart';
import '../navigator_keys.dart';
import '../navigation/rotalink_shell_routes.dart';
import '../services/campaign_push_service.dart';
import '../services/device_test_service.dart';
import '../services/app_notifications_service.dart';
import '../theme/app_colors.dart';

class AdminPopupHost extends StatefulWidget {
  const AdminPopupHost({required this.child, super.key});
  final Widget child;
  @override
  State<AdminPopupHost> createState() => _AdminPopupHostState();
}

class _AdminPopupHostState extends State<AdminPopupHost>
    with WidgetsBindingObserver {
  final _test = DeviceTestService.instance;
  final _closed = <String>{};
  List<AdminPopup> _public = [];
  Timer? _timer;
  bool _showing = false, _foreground = true, _draining = false;
  int _historyEpoch = 0;
  DateTime? _publicFetch;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _test.addListener(_changed);
    AppNotificationsService.openRequests.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_start());
    });
  }

  Future<void> _start() async {
    await _test.load();
    await _test.restorePendingTarget();
    await AppNotificationsService.loadPending();
    if (!mounted) return;
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_tick()),
    );
    await _tick();
  }

  void _changed() {
    if (_historyEpoch != _test.historyEpoch) {
      _historyEpoch = _test.historyEpoch;
      _closed.clear();
    }
    if (mounted && _foreground) unawaited(_drain());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(AppNotificationsService.syncSubscription());
    if (_foreground) unawaited(_tick());
  }

  Future<void> _tick() async {
    if (!_foreground || !mounted) return;
    if (kDebugMode && _test.paired) {
      await _test.refresh();
    } else if (_publicFetch == null ||
        DateTime.now().difference(_publicFetch!) > const Duration(minutes: 5)) {
      await _readPublic();
    }
    await _drain();
  }

  Future<void> _readPublic() async {
    _publicFetch = DateTime.now();
    final client = http.Client();
    try {
      final r = await client
          .get(Uri.parse('${AdminPopup.origin}/public/popups'))
          .timeout(const Duration(seconds: 4));
      if (r.statusCode != 200 || r.bodyBytes.length > 1024 * 1024) return;
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      if (data is! Map ||
          data['items'] is! List ||
          (data['items'] as List).length > 10) {
        return;
      }
      _public =
          (data['items'] as List)
              .map((v) => AdminPopup.parse(Map<String, dynamic>.from(v)))
              .toList()
            ..sort((a, b) => b.priority.compareTo(a.priority));
    } catch (_) {
    } finally {
      client.close();
    }
  }

  Future<void> _drain() async {
    if (_draining || _showing || !mounted || !_foreground) return;
    _draining = true;
    try {
      if (AppNotificationsService.pendingTarget != null) {
        if (rotalinkShellBodyNavigatorKey.currentState == null) return;
        final target = Map<String, String>.from(
          AppNotificationsService.pendingTarget!,
        );
        await AppNotificationsService.consumePending();
        await _open(target['route'] ?? '', target['link'] ?? '');
      }
      if (_test.pendingTarget != null) {
        final target = Map<String, String>.from(_test.pendingTarget!);
        if (rotalinkShellBodyNavigatorKey.currentState == null) return;
        await _test.consumeTarget();
        await _open(target['route'] ?? '', target['link'] ?? '');
      }
      final context = rotalinkNavigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final prefs = await SharedPreferences.getInstance(),
          key = kDebugMode && _test.paired
              ? DeviceTestService.historyKey
              : 'rotalink_popup_seen_v1';
      Map<String, String> history = {};
      try {
        history = Map<String, String>.from(
          jsonDecode(prefs.getString(key) ?? '{}'),
        );
      } catch (_) {}
      final list = kDebugMode && _test.paired ? _test.items : _public;
      for (final p in list) {
        if (!mounted || !_foreground) break;
        if (!p.eligible(DateTime.now(), history, _closed)) {
          if (p.isTest) unawaited(_test.event(p.deliveryId!, 'popup_skipped'));
          continue;
        }
        _closed.add(p.historyKey);
        history[p.historyKey] = DateTime.now().toUtc().toIso8601String();
        while (history.length > 200) {
          history.remove(history.keys.first);
        }
        await prefs.setString(key, jsonEncode(history));
        if (!context.mounted || !mounted || !_foreground) break;
        _showing = true;
        if (p.isTest) unawaited(_test.event(p.deliveryId!, 'popup_shown'));
        final clicked =
            await showDialog<bool>(
              context: context,
              barrierDismissible: true,
              builder: (dialogContext) => AdminPopupDialog(
                popup: p,
                imageHeaders: p.isTest ? _test.headers : const {},
                onClose: () => Navigator.of(dialogContext).pop(false),
                onAction: () => Navigator.of(dialogContext).pop(true),
              ),
            ) ??
            false;
        _showing = false;
        if (p.isTest) {
          unawaited(
            _test.event(
              p.deliveryId!,
              clicked ? 'popup_button' : 'popup_closed',
            ),
          );
        }
        if (clicked) await _open(p.route, p.link);
      }
    } finally {
      _draining = false;
      _showing = false;
    }
  }

  Future<void> _open(String route, String link) async {
    if (link.isNotEmpty) {
      final u = Uri.tryParse(link);
      if (u != null && u.scheme == 'https' && u.userInfo.isEmpty) {
        await launchUrl(u, mode: LaunchMode.externalApplication);
      }
      return;
    }
    if (route == 'kampanyalar') {
      CampaignPushService.requestOpen();
      return;
    }
    final target = {
      'anasayfa': RotalinkShellRoutes.home,
      'tatiller': RotalinkShellRoutes.holidays,
      'kis-kesfet': RotalinkShellRoutes.winterDiscover,
      'rota': RotalinkShellRoutes.routePlan,
      'ara': RotalinkShellRoutes.discover,
      'tesisler': RotalinkShellRoutes.discover,
      'pro': RotalinkShellRoutes.pro,
    }[route];
    if (target != null) {
      rotalinkShellBodyNavigatorKey.currentState?.pushNamed(target);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _test.removeListener(_changed);
    AppNotificationsService.openRequests.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AdminPopupDialog extends StatelessWidget {
  const AdminPopupDialog({
    required this.popup,
    required this.onClose,
    required this.onAction,
    this.imageHeaders = const {},
    super.key,
  });
  final AdminPopup popup;
  final VoidCallback onClose, onAction;
  final Map<String, String> imageHeaders;
  @override
  Widget build(BuildContext context) {
    final p = popup;
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.isTest ? 'YÖNETİCİ TESTİ' : 'ROTALİNK',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              if (p.imageUrl != null)
                Image.network(
                  p.imageUrl.toString(),
                  headers: imageHeaders,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (_, error, stack) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      p.title,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textStrongOf(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      p.body,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: AppColors.textMutedOf(context),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (p.buttonLabel.isNotEmpty &&
                        (p.link.isNotEmpty || p.route.isNotEmpty))
                      FilledButton(
                        onPressed: onAction,
                        child: Text(p.buttonLabel),
                      ),
                    TextButton(onPressed: onClose, child: const Text('Kapat')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
