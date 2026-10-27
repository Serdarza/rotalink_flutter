import 'package:flutter/material.dart';
import '../services/feedback_service.dart';
import '../models/misafirhane.dart';
import '../theme/app_colors.dart';

class FeedbackContactFields extends StatelessWidget {
  const FeedbackContactFields({
    super.key,
    required this.controller,
    required this.consent,
    required this.onConsentChanged,
    this.showEmail = true,
  });
  final TextEditingController controller;
  final bool consent, showEmail;
  final ValueChanged<bool> onConsentChanged;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (showEmail)
        TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          maxLength: 254,
          decoration: const InputDecoration(
            labelText: 'E-posta (isteğe bağlı)',
            counterText: '',
          ),
        ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => value.text.trim().isEmpty
            ? const SizedBox.shrink()
            : CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: consent,
                onChanged: (v) => onConsentChanged(v ?? false),
                title: const Text(
                  'E-posta adresimin yalnızca bu bildirim için geri dönüş amacıyla kullanılmasına izin veriyorum.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
      ),
    ],
  );
}

class FeedbackReportButton extends StatelessWidget {
  const FeedbackReportButton({
    super.key,
    required this.sourcePage,
    this.facilityId = '',
    this.facilityName = '',
    this.facility,
  });
  final String sourcePage, facilityId, facilityName;
  final Misafirhane? Function()? facility;
  @override
  Widget build(BuildContext context) => FloatingActionButton.small(
    heroTag: 'rotalink-feedback',
    tooltip: 'Hata, şikâyet veya öneri bildir',
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    onPressed: () {
      final selectedFacility = facility?.call();
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => FeedbackReportForm(
          sourcePage: sourcePage,
          facilityId: selectedFacility?.stableFacilityId ?? facilityId,
          facilityName: selectedFacility?.isim ?? facilityName,
        ),
      );
    },
    child: const Icon(Icons.feedback_outlined),
  );
}

class FeedbackReportForm extends StatefulWidget {
  const FeedbackReportForm({
    super.key,
    required this.sourcePage,
    this.facilityId = '',
    this.facilityName = '',
    this.service,
  });
  final String sourcePage, facilityId, facilityName;
  final FeedbackService? service;
  @override
  State<FeedbackReportForm> createState() => _FeedbackReportFormState();
}

class _FeedbackReportFormState extends State<FeedbackReportForm> {
  final _description = TextEditingController(),
      _email = TextEditingController();
  FeedbackKind _kind = FeedbackKind.bug;
  bool _consent = false, _sending = false;
  String? _error;
  @override
  void dispose() {
    _description.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await (widget.service ?? FeedbackService.instance).submit(
        kind: _kind,
        description: _description.text,
        sourcePage: widget.sourcePage,
        facilityId: widget.facilityId,
        facilityName: widget.facilityName,
        email: _email.text,
        contactConsent: _consent,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Teşekkürler, bildiriminiz alındı.')),
      );
    } on FeedbackException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bize bildirin',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (widget.facilityName.isNotEmpty) Text(widget.facilityName),
          const SizedBox(height: 12),
          DropdownButtonFormField<FeedbackKind>(
            initialValue: _kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bildirim türü'),
            items: FeedbackKind.values
                .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                .toList(),
            onChanged: _sending ? null : (v) => setState(() => _kind = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 7,
            maxLength: 6000,
            decoration: const InputDecoration(
              labelText: 'Açıklama',
              hintText: 'Size nasıl yardımcı olabiliriz?',
            ),
          ),
          FeedbackContactFields(
            controller: _email,
            consent: _consent,
            onConsentChanged: (v) => setState(() => _consent = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_sending ? 'Gönderiliyor…' : 'Gönder'),
          ),
        ],
      ),
    ),
  );
}
