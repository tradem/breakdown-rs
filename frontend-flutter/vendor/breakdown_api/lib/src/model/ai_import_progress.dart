// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/ai_import_stage.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_progress.g.dart';

/// Live progress of a running AI import job (issue #664).  Additive and optional on [`AiImportJob`]: `None` for jobs that have not reached a `mark_progress` call yet (fresh `pending` claims, retried attempts before their first stage boundary — the claim SQL resets it).
///
/// Properties:
/// * [chunk] - 1-based index of the chunk currently being processed or just completed; `None` when the stage carries no chunk notion.
/// * [chunksTotal] - Total chunks in the document (known once chunking finishes).
/// * [episodesSeen] - Human-readable episode labels discovered so far, in first-seen order, deduplicated (e.g. `[\"Ep. 3\", \"Ep. 4\"]`). Built at zero extra LLM token cost from the deterministic `Ep.:` marker scan and per-chunk extracted `DraftEpisode` metadata — never script prose.
/// * [stage]
@BuiltValue()
abstract class AiImportProgress
    implements Built<AiImportProgress, AiImportProgressBuilder> {
  /// 1-based index of the chunk currently being processed or just completed; `None` when the stage carries no chunk notion.
  @BuiltValueField(wireName: r'chunk')
  int? get chunk;

  /// Total chunks in the document (known once chunking finishes).
  @BuiltValueField(wireName: r'chunks_total')
  int? get chunksTotal;

  /// Human-readable episode labels discovered so far, in first-seen order, deduplicated (e.g. `[\"Ep. 3\", \"Ep. 4\"]`). Built at zero extra LLM token cost from the deterministic `Ep.:` marker scan and per-chunk extracted `DraftEpisode` metadata — never script prose.
  @BuiltValueField(wireName: r'episodes_seen')
  BuiltList<String>? get episodesSeen;

  @BuiltValueField(wireName: r'stage')
  AiImportStage get stage;
  // enum stageEnum {  extracting_text,  extracting,  merging,  storing_preview,  };

  AiImportProgress._();

  factory AiImportProgress([void updates(AiImportProgressBuilder b)]) =
      _$AiImportProgress;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportProgressBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportProgress> get serializer =>
      _$AiImportProgressSerializer();
}

class _$AiImportProgressSerializer
    implements PrimitiveSerializer<AiImportProgress> {
  @override
  final Iterable<Type> types = const [AiImportProgress, _$AiImportProgress];

  @override
  final String wireName = r'AiImportProgress';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.chunk != null) {
      yield r'chunk';
      yield serializers.serialize(
        object.chunk,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.chunksTotal != null) {
      yield r'chunks_total';
      yield serializers.serialize(
        object.chunksTotal,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.episodesSeen != null) {
      yield r'episodes_seen';
      yield serializers.serialize(
        object.episodesSeen,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    yield r'stage';
    yield serializers.serialize(
      object.stage,
      specifiedType: const FullType(AiImportStage),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiImportProgress object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AiImportProgressBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'chunk':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.chunk = valueDes;
          break;
        case r'chunks_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.chunksTotal = valueDes;
          break;
        case r'episodes_seen':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(String)]),
          ) as BuiltList<String>?;
          if (valueDes == null) continue;
          result.episodesSeen.replace(valueDes);
          break;
        case r'stage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AiImportStage),
          ) as AiImportStage;
          result.stage = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiImportProgress deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportProgressBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}
