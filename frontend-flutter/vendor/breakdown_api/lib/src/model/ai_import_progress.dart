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
/// * [chunk] - Chunk counter of the extraction progress. `0` is a deliberate published state — \"chunking finished, the first chunk has not yet completed\" (the frame emitted right after the deterministic scan) — so the schema floor is 0, not 1. For every later frame this is the 1-based index of the last **completed** chunk (`1..=chunks_total`).
/// * [chunksTotal] - Total chunks in the document (known once chunking finishes).
/// * [doneBytes] - Source-text bytes already extracted (issue #762), summed over the **completed** chunks. `0` is a deliberate published state, mirroring [`Self::chunk`].  Chunk cost is heterogeneous by an order of magnitude — one chunk is one scene and scene lengths differ wildly — so a byte denominator is a materially better ETA basis than a chunk count. Additive with `serde(default)`: `None` when the worker has no byte budget for the job (a schedule job is a single extraction unit).
/// * [episodesSeen] - Human-readable episode labels discovered so far, in first-seen order, deduplicated (e.g. `[\"Ep. 3\", \"Ep. 4\"]`). Built at zero extra LLM token cost from the deterministic `Ep.:` marker scan and per-chunk extracted `DraftEpisode` metadata — never script prose.
/// * [stage]
/// * [startedAt] - When the **current attempt** was claimed (issue #762).  The time anchor the counters above lack: without it a client can only run a stopwatch while its own screen stays open, and a reconnecting or restarted client can never reconstruct a rate from `chunk`/`chunks_total` alone. Every frame of one attempt carries the same value, so a client can recompute the estimate on every frame without accumulating state.  Additive with `serde(default)`: frames written before the field existed deserialize as `None`, and a client then simply shows no estimate — never a fabricated one. A retry starts cleanly because the claim clears [`Self::chunk`]/[`Self::done_bytes`] and writes a fresh anchor.
/// * [totalBytes] - Total source-text bytes the document splits into (issue #762), known once the deterministic chunk scan finishes. Same `serde(default)` contract as [`Self::done_bytes`]; a client prefers the byte pair when `total_bytes > 0` and falls back to the chunk counters otherwise.
@BuiltValue()
abstract class AiImportProgress
    implements Built<AiImportProgress, AiImportProgressBuilder> {
  /// Chunk counter of the extraction progress. `0` is a deliberate published state — \"chunking finished, the first chunk has not yet completed\" (the frame emitted right after the deterministic scan) — so the schema floor is 0, not 1. For every later frame this is the 1-based index of the last **completed** chunk (`1..=chunks_total`).
  @BuiltValueField(wireName: r'chunk')
  int? get chunk;

  /// Total chunks in the document (known once chunking finishes).
  @BuiltValueField(wireName: r'chunks_total')
  int? get chunksTotal;

  /// Source-text bytes already extracted (issue #762), summed over the **completed** chunks. `0` is a deliberate published state, mirroring [`Self::chunk`].  Chunk cost is heterogeneous by an order of magnitude — one chunk is one scene and scene lengths differ wildly — so a byte denominator is a materially better ETA basis than a chunk count. Additive with `serde(default)`: `None` when the worker has no byte budget for the job (a schedule job is a single extraction unit).
  @BuiltValueField(wireName: r'done_bytes')
  int? get doneBytes;

  /// Human-readable episode labels discovered so far, in first-seen order, deduplicated (e.g. `[\"Ep. 3\", \"Ep. 4\"]`). Built at zero extra LLM token cost from the deterministic `Ep.:` marker scan and per-chunk extracted `DraftEpisode` metadata — never script prose.
  @BuiltValueField(wireName: r'episodes_seen')
  BuiltList<String>? get episodesSeen;

  @BuiltValueField(wireName: r'stage')
  AiImportStage get stage;
  // enum stageEnum {  extracting_text,  extracting,  merging,  storing_preview,  };

  /// When the **current attempt** was claimed (issue #762).  The time anchor the counters above lack: without it a client can only run a stopwatch while its own screen stays open, and a reconnecting or restarted client can never reconstruct a rate from `chunk`/`chunks_total` alone. Every frame of one attempt carries the same value, so a client can recompute the estimate on every frame without accumulating state.  Additive with `serde(default)`: frames written before the field existed deserialize as `None`, and a client then simply shows no estimate — never a fabricated one. A retry starts cleanly because the claim clears [`Self::chunk`]/[`Self::done_bytes`] and writes a fresh anchor.
  @BuiltValueField(wireName: r'started_at')
  DateTime? get startedAt;

  /// Total source-text bytes the document splits into (issue #762), known once the deterministic chunk scan finishes. Same `serde(default)` contract as [`Self::done_bytes`]; a client prefers the byte pair when `total_bytes > 0` and falls back to the chunk counters otherwise.
  @BuiltValueField(wireName: r'total_bytes')
  int? get totalBytes;

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
    if (object.doneBytes != null) {
      yield r'done_bytes';
      yield serializers.serialize(
        object.doneBytes,
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
    if (object.startedAt != null) {
      yield r'started_at';
      yield serializers.serialize(
        object.startedAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    if (object.totalBytes != null) {
      yield r'total_bytes';
      yield serializers.serialize(
        object.totalBytes,
        specifiedType: const FullType.nullable(int),
      );
    }
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
        case r'done_bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.doneBytes = valueDes;
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
        case r'started_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.startedAt = valueDes;
          break;
        case r'total_bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.totalBytes = valueDes;
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
