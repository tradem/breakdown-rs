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
/// * [blockNumber] - The production block number the script's page headers state, or the model's answer when the deterministic `Block:` scan found no marker (issue #827). `None` means \"the script does not state one\" — never a fabricated number, and never the job's import TARGET ([`AiImportTarget::block_number`]), which is a separate fact: only because the two travel side by side can a client show \"script says 2 · importing into 1\" and flag a mismatch before the apply's cross-block guard fires.  Additive with `serde(default)`: frames written before the field existed deserialize as `None`, and a client then renders the import target as the associated block instead of an empty field.
/// * [chunk] - Chunk counter of the extraction progress. `0` is a deliberate published state — \"chunking finished, the first chunk has not yet completed\" (the frame emitted right after the deterministic scan) — so the schema floor is 0, not 1. For every later frame this is the 1-based index of the last **completed** chunk (`1..=chunks_total`).
/// * [chunksTotal] - Total chunks in the document (known once chunking finishes).
/// * [doneBytes] - Source-text bytes already extracted (issue #762), summed over the **completed** chunks. `0` is a deliberate published state, mirroring [`Self::chunk`].  Chunk cost is heterogeneous by an order of magnitude — one chunk is one scene and scene lengths differ wildly — so a byte denominator is a materially better ETA basis than a chunk count. Additive with `serde(default)`: `None` when the worker has no byte budget for the job (a schedule job is a single extraction unit).
/// * [episodesSeen] - Human-readable episode labels discovered so far, in first-seen order, deduplicated (e.g. `[\"Ep. 3\", \"Ep. 4\"]`). Built at zero extra LLM token cost from the deterministic `Ep.:` marker scan and per-chunk extracted `DraftEpisode` metadata — never script prose.
/// * [resumedFrom] - How many chunks this attempt **resumed from** (issue #871, D-B5).  `Some(n)` means \"`n` chunks are already stored and paid for; this attempt continues at chunk `n + 1`\". It is the honest counterpart of [`Self::chunk`], which keeps its documented meaning (\"1-based index of the last completed chunk **of this attempt**\") — so a resumed attempt's first frame reports `chunk = resumed_from`, and the bar does not snap back to zero.  It exists because the counters alone are ambiguous: with `chunk = 25` and `resumed_from = 25`, a client that derived a rate from `chunk` alone would report \"25 chunks in one second\" and then declare a healthy successor chunk stalled. The client therefore computes the rate from `chunk - resumed_from` and the remaining count from `chunks_total - chunk`.  Additive with `serde(default)`: pre-#871 frames read as `None`, and a client then estimates exactly as it did before — nothing is fabricated.
/// * [stage]
/// * [startedAt] - When the **current attempt** was claimed (issue #762).  The time anchor the counters above lack: without it a client can only run a stopwatch while its own screen stays open, and a reconnecting or restarted client can never reconstruct a rate from `chunk`/`chunks_total` alone. Every frame of one attempt carries the same value, so a client can recompute the estimate on every frame without accumulating state.  Additive with `serde(default)`: frames written before the field existed deserialize as `None`, and a client then simply shows no estimate — never a fabricated one. A retry starts cleanly because the claim clears [`Self::chunk`]/[`Self::done_bytes`] and writes a fresh anchor.
/// * [totalBytes] - Total source-text bytes the document splits into (issue #762), known once the deterministic chunk scan finishes. Same `serde(default)` contract as [`Self::done_bytes`]; a client prefers the byte pair when `total_bytes > 0` and falls back to the chunk counters otherwise.
/// * [writtenAt] - When **this frame** was written, on the server's clock (issue #762).  The end of the measured interval: `written_at - started_at` is extraction time, whereas a client-side \"now\" also counts every second the screen was closed, backgrounded or offline — which inflates the per-unit cost and with it the estimate. A heartbeat-driven `updated_at` is no substitute (a live worker refreshes it continuously), so the stamp travels with the frame it describes.  Additive with `serde(default)`: a frame written before the field existed deserializes as `None`, and a client then falls back to its own clock as it did before.
@BuiltValue()
abstract class AiImportProgress
    implements Built<AiImportProgress, AiImportProgressBuilder> {
  /// The production block number the script's page headers state, or the model's answer when the deterministic `Block:` scan found no marker (issue #827). `None` means \"the script does not state one\" — never a fabricated number, and never the job's import TARGET ([`AiImportTarget::block_number`]), which is a separate fact: only because the two travel side by side can a client show \"script says 2 · importing into 1\" and flag a mismatch before the apply's cross-block guard fires.  Additive with `serde(default)`: frames written before the field existed deserialize as `None`, and a client then renders the import target as the associated block instead of an empty field.
  @BuiltValueField(wireName: r'block_number')
  int? get blockNumber;

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

  /// How many chunks this attempt **resumed from** (issue #871, D-B5).  `Some(n)` means \"`n` chunks are already stored and paid for; this attempt continues at chunk `n + 1`\". It is the honest counterpart of [`Self::chunk`], which keeps its documented meaning (\"1-based index of the last completed chunk **of this attempt**\") — so a resumed attempt's first frame reports `chunk = resumed_from`, and the bar does not snap back to zero.  It exists because the counters alone are ambiguous: with `chunk = 25` and `resumed_from = 25`, a client that derived a rate from `chunk` alone would report \"25 chunks in one second\" and then declare a healthy successor chunk stalled. The client therefore computes the rate from `chunk - resumed_from` and the remaining count from `chunks_total - chunk`.  Additive with `serde(default)`: pre-#871 frames read as `None`, and a client then estimates exactly as it did before — nothing is fabricated.
  @BuiltValueField(wireName: r'resumed_from')
  int? get resumedFrom;

  @BuiltValueField(wireName: r'stage')
  AiImportStage get stage;
  // enum stageEnum {  extracting_text,  extracting,  merging,  storing_preview,  };

  /// When the **current attempt** was claimed (issue #762).  The time anchor the counters above lack: without it a client can only run a stopwatch while its own screen stays open, and a reconnecting or restarted client can never reconstruct a rate from `chunk`/`chunks_total` alone. Every frame of one attempt carries the same value, so a client can recompute the estimate on every frame without accumulating state.  Additive with `serde(default)`: frames written before the field existed deserialize as `None`, and a client then simply shows no estimate — never a fabricated one. A retry starts cleanly because the claim clears [`Self::chunk`]/[`Self::done_bytes`] and writes a fresh anchor.
  @BuiltValueField(wireName: r'started_at')
  DateTime? get startedAt;

  /// Total source-text bytes the document splits into (issue #762), known once the deterministic chunk scan finishes. Same `serde(default)` contract as [`Self::done_bytes`]; a client prefers the byte pair when `total_bytes > 0` and falls back to the chunk counters otherwise.
  @BuiltValueField(wireName: r'total_bytes')
  int? get totalBytes;

  /// When **this frame** was written, on the server's clock (issue #762).  The end of the measured interval: `written_at - started_at` is extraction time, whereas a client-side \"now\" also counts every second the screen was closed, backgrounded or offline — which inflates the per-unit cost and with it the estimate. A heartbeat-driven `updated_at` is no substitute (a live worker refreshes it continuously), so the stamp travels with the frame it describes.  Additive with `serde(default)`: a frame written before the field existed deserializes as `None`, and a client then falls back to its own clock as it did before.
  @BuiltValueField(wireName: r'written_at')
  DateTime? get writtenAt;

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
    if (object.blockNumber != null) {
      yield r'block_number';
      yield serializers.serialize(
        object.blockNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
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
    if (object.resumedFrom != null) {
      yield r'resumed_from';
      yield serializers.serialize(
        object.resumedFrom,
        specifiedType: const FullType.nullable(int),
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
    if (object.writtenAt != null) {
      yield r'written_at';
      yield serializers.serialize(
        object.writtenAt,
        specifiedType: const FullType.nullable(DateTime),
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
        case r'block_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.blockNumber = valueDes;
          break;
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
        case r'resumed_from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.resumedFrom = valueDes;
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
        case r'written_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.writtenAt = valueDes;
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
