import 'package:flutter/material.dart';
import '../services/feedback_service.dart';
import '../widgets/feedback_report_button.dart';
import '../l10n/app_strings.dart';
import '../theme/app_colors.dart';

const _sendBg = AppColors.primary;

/// Kotlin [SuggestionActivity] + [activity_suggestion.xml].
class SuggestionScreen extends StatefulWidget {
  const SuggestionScreen({super.key});

  @override
  State<SuggestionScreen> createState() => _SuggestionScreenState();
}

class _SuggestionScreenState extends State<SuggestionScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _suggestion = TextEditingController();

  bool _sending = false;
  bool _consent = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _suggestion.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final email = _email.text.trim();
    final suggestion = _suggestion.text.trim();
    if (suggestion.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Lütfen önerinizi yazın.')));
      return;
    }

    final name = _name.text.trim();
    setState(() => _sending = true);
    try {
      await FeedbackService.instance.submit(
        kind: FeedbackKind.suggestion,
        description: name.isEmpty
            ? suggestion
            : 'Ad Soyad: $name\n\n$suggestion',
        sourcePage: 'Menü / Öneri',
        email: email,
        contactConsent: _consent,
      );
      if (mounted) _showThankYouDialog();
    } on FeedbackException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
      backgroundColor: AppColors.canvasOf(context),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.surfaceOf(context),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              padding: EdgeInsets.fromLTRB(8, top + 8, 8, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textStrongOf(context),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppStrings.suggestionTitle,
                      style: TextStyle(
                        color: AppColors.textStrongOf(context),
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      AppStrings.suggestionSubtitle,
                      style: TextStyle(
                        color: AppColors.textMutedOf(context),
                        fontSize: 14,
                      ),
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
                16 +
                    MediaQuery.viewInsetsOf(context).bottom +
                    MediaQuery.viewPaddingOf(context).bottom,
              ),
              child: Card(
                color: AppColors.surfaceOf(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _name,
                        decoration: InputDecoration(
                          hintText: AppStrings.suggestionNameHint,
                          border: InputBorder.none,
                          filled: true,
                          fillColor: AppColors.fieldFillOf(context),
                          contentPadding: EdgeInsets.all(12),
                        ),
                        style: TextStyle(
                          color: AppColors.searchTextOf(context),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _email,
                        decoration: InputDecoration(
                          hintText: 'E-posta adresiniz (isteğe bağlı)',
                          border: InputBorder.none,
                          filled: true,
                          fillColor: AppColors.fieldFillOf(context),
                          contentPadding: EdgeInsets.all(12),
                        ),
                        style: TextStyle(
                          color: AppColors.searchTextOf(context),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                      ),
                      FeedbackContactFields(
                        controller: _email,
                        consent: _consent,
                        showEmail: false,
                        onConsentChanged: (v) => setState(() => _consent = v),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _suggestion,
                        decoration: InputDecoration(
                          hintText: AppStrings.suggestionBodyHint,
                          border: InputBorder.none,
                          filled: true,
                          fillColor: AppColors.fieldFillOf(context),
                          contentPadding: EdgeInsets.all(16),
                          alignLabelWithHint: true,
                        ),
                        style: TextStyle(
                          color: AppColors.searchTextOf(context),
                        ),
                        minLines: 6,
                        maxLines: 12,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _sending ? null : _send,
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
