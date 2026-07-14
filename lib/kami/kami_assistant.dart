import 'package:flutter/material.dart';

/// Sohbet mesajı rolü — ileride AI yanıtları için hazır.
enum KamiMessageRole { user, assistant, system }

/// Tek bir sohbet satırı.
@immutable
class KamiChatMessage {
  const KamiChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.metadata,
  });

  final String id;
  final KamiMessageRole role;
  final String text;
  final DateTime createdAt;

  /// İleride rota/tesis kartları, konum ipuçları vb. için.
  final Map<String, Object?>? metadata;
}

/// KAMİ yetenek alanları — AI entegrasyonunda tool/intent eşlemesi için.
enum KamiCapability {
  chat,
  routePlanning,
  publicFacilitySuggest,
  municipalFacilitySuggest,
  sightseeingSuggest,
  foodSuggest,
  voiceInput,
  locationAnalysis,
  roadsideFacilities,
}

/// AI / backend sağlayıcı sözleşmesi.
///
/// Gemini, OpenAI veya özel servis bu arayüzü uygular.
abstract class KamiAssistantService {
  Future<KamiChatMessage> sendMessage({
    required String text,
    required List<KamiChatMessage> history,
    Map<String, Object?>? context,
  });

  /// Sesli giriş vb. için ileride genişletilebilir.
  Stream<String>? get partialReplies => null;

  void dispose() {}
}

/// Şimdilik gerçek AI yok — yerel [KamiService] tercih edilir.
/// Bu stub yalnızca test / fallback içindir.
class KamiStubAssistantService implements KamiAssistantService {
  @override
  Future<KamiChatMessage> sendMessage({
    required String text,
    required List<KamiChatMessage> history,
    Map<String, Object?>? context,
  }) async {
    // Bilinçli olarak boş: ileride burada sağlayıcı yanıtı dönecek.
    return KamiChatMessage(
      id: 'stub_${DateTime.now().microsecondsSinceEpoch}',
      role: KamiMessageRole.assistant,
      text: '',
      createdAt: DateTime.now(),
      metadata: const {'stub': true},
    );
  }

  @override
  Stream<String>? get partialReplies => null;

  @override
  void dispose() {}
}

/// Sohbet durumu — chip → input, gönder, ileride AI yanıtı.
class KamiChatController extends ChangeNotifier {
  KamiChatController({KamiAssistantService? service})
      : _service = service ?? KamiStubAssistantService();

  final KamiAssistantService _service;
  final List<KamiChatMessage> _messages = <KamiChatMessage>[];
  final TextEditingController inputController = TextEditingController();

  bool _sending = false;

  List<KamiChatMessage> get messages => List.unmodifiable(_messages);
  bool get isSending => _sending;
  bool get hasConversation =>
      _messages.any((m) =>
          m.text.trim().isNotEmpty ||
          (m.metadata != null && m.metadata!['ui'] == 'facility_cards'));

  void setInputText(String text) {
    inputController.text = text;
    inputController.selection = TextSelection.collapsed(offset: text.length);
    notifyListeners();
  }

  /// Sohbeti sıfırlar — geri tuşu önce karşılama ekranına döner.
  void clearConversation() {
    if (_messages.isEmpty && !_sending) return;
    _messages.clear();
    inputController.clear();
    _sending = false;
    notifyListeners();
  }

  /// Kullanıcı mesajını ekler; boş asistan yanıtı yok sayılır (kartlı UI hariç).
  Future<void> submitCurrentInput() async {
    final text = inputController.text.trim();
    if (text.isEmpty || _sending) return;

    final userMsg = KamiChatMessage(
      id: 'u_${DateTime.now().microsecondsSinceEpoch}',
      role: KamiMessageRole.user,
      text: text,
      createdAt: DateTime.now(),
    );
    _messages.add(userMsg);
    inputController.clear();
    _sending = true;
    notifyListeners();

    try {
      final reply = await _service.sendMessage(
        text: text,
        history: List<KamiChatMessage>.unmodifiable(_messages),
      );
      final hasCards = reply.metadata?['ui'] == 'facility_cards';
      if (reply.text.trim().isNotEmpty || hasCards) {
        _messages.add(reply);
      }
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    inputController.dispose();
    _service.dispose();
    super.dispose();
  }
}
