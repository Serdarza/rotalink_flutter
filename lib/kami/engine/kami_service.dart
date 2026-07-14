import '../kami_assistant.dart';
import 'city_resolver.dart';
import 'intent_detector.dart';
import 'kami_models.dart';
import 'kami_system_instruction.dart';
import 'response_builder.dart';
import 'rule_engine.dart';

/// Yerel KAMİ orkestratörü: Intent → Rule → Response.
///
/// Davranış kuralları: [KamiSystemInstruction.text]
/// Gemini/OpenAI yok. İleride [KamiAssistantService] yerine başka
/// implementasyon enjekte edilebilir.
class KamiService implements KamiAssistantService {
  KamiService({
    required this.contextProvider,
    KamiRuleEngine? engine,
  }) : engine = engine ?? KamiRuleEngine();

  /// KAMİ sistem yönergesi — bölgesel öneri ve veri kaynağı kuralları.
  static String get systemInstruction => KamiSystemInstruction.text;
  /// Her istekte güncel RTDB snapshot + konum.
  final Future<KamiQueryContext?> Function() contextProvider;
  final KamiRuleEngine engine;

  @override
  Future<KamiChatMessage> sendMessage({
    required String text,
    required List<KamiChatMessage> history,
    Map<String, Object?>? context,
  }) async {
    final ctx = await contextProvider();
    if (ctx == null) {
      return _msg(
        'Veriler henüz yüklenmedi. Birkaç saniye sonra tekrar deneyin.',
        intent: KamiIntentType.unknown.name,
      );
    }

    final catalog = KamiCityResolver.buildCatalog(_citiesFromData(ctx));
    var intent = KamiIntentDetector.detect(text, cityCatalog: catalog);

    // Düşük güven → veritabanı metin araması dene
    if (intent.confidence < 0.5 && intent.type != KamiIntentType.unknown) {
      final dbPayload = await engine.execute(
        intent: DetectedIntent(
          type: KamiIntentType.databaseSearch,
          rawText: text,
          confidence: 0.4,
          entities: intent.entities,
        ),
        context: ctx,
      );
      if (!dbPayload.isEmpty) {
        return _buildMessage(dbPayload, intent);
      }
    }

    final payload = await engine.execute(intent: intent, context: ctx);

    // Boş veya düşük güven → şehir + konu ile veritabanı araması
    if ((payload.isEmpty || intent.confidence < 0.75) &&
        intent.type != KamiIntentType.databaseSearch) {
      final city = intent.city ?? intent.entities?.primaryCity;
      final dbPayload = await engine.execute(
        intent: DetectedIntent(
          type: KamiIntentType.databaseSearch,
          city: city,
          rawText: text,
          confidence: 0.5,
          entities: intent.entities,
        ),
        context: ctx,
      );
      if (!dbPayload.isEmpty) {
        return _buildMessage(dbPayload, intent);
      }
    }

    return _buildMessage(payload, intent);
  }

  KamiChatMessage _buildMessage(KamiPayload payload, DetectedIntent intent) {
    final answer = KamiResponseBuilder.build(payload);
    final cards = KamiResponseBuilder.buildResultCards(payload);
    final destinationRecs = payload.cityScores;
    final useRouteRecs =
        payload.intent == KamiIntentType.route && destinationRecs.isNotEmpty;
    final useWeekend =
        payload.intent == KamiIntentType.weekendTrip && destinationRecs.isNotEmpty;
    final useDestinationRecs = useWeekend || useRouteRecs;
    final useCards = !useDestinationRecs &&
        KamiResponseBuilder.usesResultCards(payload.intent) &&
        cards.isNotEmpty;

    return _msg(
      answer.isEmpty && (useCards || useDestinationRecs) ? payload.title : answer,
      intent: payload.intent.name,
      metadata: {
        'intent': payload.intent.name,
        'confidence': intent.confidence,
        'city': intent.city,
        'fromCity': intent.fromCity,
        'toCity': intent.toCity,
        'facilityCount': payload.facilities.length,
        'geziCount': payload.gezi.length,
        'yemekCount': payload.yemek.length,
        'sosyalCount': payload.sosyal.length,
        'routeSections': payload.routeSections.length,
        'source': 'rotalink_database',
        if (useDestinationRecs)
          'ui': useRouteRecs ? 'route_recs' : 'weekend_recs',
        if (useDestinationRecs) 'title': payload.title,
        if (useDestinationRecs) 'subtitle': payload.subtitle,
        if (useDestinationRecs)
          'recommendations': [for (final s in destinationRecs) s.toMap()],
        if (useDestinationRecs && payload.userLocation != null) ...{
          'userLat': payload.userLocation!.latitude,
          'userLon': payload.userLocation!.longitude,
        },
        if (useRouteRecs && payload.cities.isNotEmpty)
          'homeCity': payload.cities.first,
        if (useCards) 'ui': 'facility_cards',
        if (useCards) 'title': payload.title,
        if (useCards) 'subtitle': payload.subtitle,
        if (useCards) 'cards': [for (final c in cards) c.toMap()],
      },
    );
  }

  Iterable<String> _citiesFromData(KamiQueryContext ctx) sync* {
    for (final m in ctx.data.aramaIcinTumTesisler) {
      if (m.il.trim().isNotEmpty) yield m.il;
    }
    for (final g in ctx.data.gezi) {
      if (g.il.trim().isNotEmpty) yield g.il;
    }
    for (final y in ctx.data.yemek) {
      if (y.il.trim().isNotEmpty) yield y.il;
    }
    for (final s in ctx.data.sosyal) {
      if (s.il.trim().isNotEmpty) yield s.il;
    }
  }

  KamiChatMessage _msg(
    String text, {
    required String intent,
    Map<String, Object?>? metadata,
  }) {
    return KamiChatMessage(
      id: 'kami_${DateTime.now().microsecondsSinceEpoch}',
      role: KamiMessageRole.assistant,
      text: text,
      createdAt: DateTime.now(),
      metadata: {
        'engine': 'rule',
        'intent': intent,
        ...?metadata,
      },
    );
  }

  @override
  Stream<String>? get partialReplies => null;

  @override
  void dispose() {}
}
