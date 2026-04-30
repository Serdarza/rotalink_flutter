import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

const _headerTop = Color(0xFF005F6B);
const _headerBottom = Color(0xFF008898);
const _pageBg = Color(0xFFF5FDFE);
const _fieldBg = Color(0xFFFFFFFF);
const _fieldText = Color(0xFF222222);
const _sendBg = Color(0xFF007B8F);

/// Kotlin [SuggestionActivity] + [activity_suggestion.xml].
class SuggestionScreen extends StatefulWidget {
  const SuggestionScreen({super.key});

  @override
  State<SuggestionScreen> createState() => _SuggestionScreenState();
}

class _SuggestionScreenState extends State<SuggestionScreen>
    with WidgetsBindingObserver {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _suggestion = TextEditingController();

  bool _mailLaunched = false;

  static const _to = 'rotalinkinfo@gmail.com';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _email.dispose();
    _suggestion.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _mailLaunched && mounted) {
      setState(() => _mailLaunched = false);
      _showThankYouDialog();
    }
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    final suggestion = _suggestion.text.trim();
    if (email.isEmpty || suggestion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.suggestionValidationToast)),
      );
      return;
    }

    final name = _name.text.trim();
    final body =
        '''
Ad Soyad: $name
Kullanıcı E-posta: $email

Öneri:
$suggestion'''
            .trim();

    final uri = Uri(
      scheme: 'mailto',
      path: _to,
      query: _encodeQueryParameters(<String, String>{
        'subject': 'Kullanıcı Önerisi',
        'body': body,
      }),
    );

    final ok = await launchUrl(uri);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.suggestionMailFailed)),
      );
      return;
    }
    setState(() => _mailLaunched = true);
  }

  String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map(
          (e) =>
              '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
        )
        .join('&');
  }

  void _showThankYouDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(AppStrings.suggestionThanksTitle),
          content: const Text(AppStrings.suggestionThanksMessage),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text(AppStrings.suggestionOk),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _pageBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 8,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_headerTop, _headerBottom],
                ),
              ),
              padding: EdgeInsets.fromLTRB(8, top + 8, 8, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: AppColors.white),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppStrings.suggestionTitle,
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppStrings.suggestionSubtitle,
                      style: TextStyle(color: Color(0xFFB0E8EE), fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom + MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Card(
                elevation: 4,
                color: _fieldBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                          hintText: AppStrings.suggestionNameHint,
                          border: InputBorder.none,
                          filled: true,
                          fillColor: _fieldBg,
                          contentPadding: EdgeInsets.all(12),
                        ),
                        style: const TextStyle(color: _fieldText),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _email,
                        decoration: const InputDecoration(
                          hintText: AppStrings.suggestionEmailHint,
                          border: InputBorder.none,
                          filled: true,
                          fillColor: _fieldBg,
                          contentPadding: EdgeInsets.all(12),
                        ),
                        style: const TextStyle(color: _fieldText),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _suggestion,
                        decoration: const InputDecoration(
                          hintText: AppStrings.suggestionBodyHint,
                          border: InputBorder.none,
                          filled: true,
                          fillColor: _fieldBg,
                          contentPadding: EdgeInsets.all(16),
                          alignLabelWithHint: true,
                        ),
                        style: const TextStyle(color: _fieldText),
                        minLines: 6,
                        maxLines: 12,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _send,
                          style: FilledButton.styleFrom(
                            backgroundColor: _sendBg,
                            foregroundColor: AppColors.white,
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: const Text(AppStrings.suggestionSend),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
