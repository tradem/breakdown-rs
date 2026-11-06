// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_target.g.dart';

/// The production target an AI import writes into, snapshotted at dispatch (issue #771).  A job's authoritative write target is the block in `X-Active-Block`; the season follows from that block. Nothing on the wire named the target, so a client could only *believe* it knew where its rows would land — the reported defect was a freshly created season whose import silently went into the previous season's block. This snapshot records WHERE the upload declared it was going, resolved at the API edge from the read models (`GET /v1/blocks/{id}` + `GET /v1/seasons/{id}`) — never invented, and never from a second projection lookup inside the write path (CQRS boundary: the handler is the legitimate consumer).  The numbers are the production-global identities a user speaks in (`Season {n}` / `Block {n}`); they are display metadata, so a failed season read degrades the whole snapshot to `None` rather than blocking the upload.  Since issue #829 the target may name a season **without** a block: an upload is allowed to omit `X-Active-Block` and declare only `X-Declared-Season`, in which case the job starts block-less and the block is attached later (`PUT /v1/ai-import/jobs/{id}/target`). The season pair is then always known while [`Self::block_number`] stays `None` until the attach.
///
/// Properties:
/// * [blockNumber] - The block's production-global number (the block itself is [`AiImportJob::block_id`]). `None` means \"no target block chosen yet\" (issue #829) — honest absence, never `0` and never a placeholder.
/// * [seasonId] - The season the imported rows land in (the owning season of the job's block, or the declared season of a block-less upload).
/// * [seasonNumber] - The season's production-global number.
@BuiltValue()
abstract class AiImportTarget
    implements Built<AiImportTarget, AiImportTargetBuilder> {
  /// The block's production-global number (the block itself is [`AiImportJob::block_id`]). `None` means \"no target block chosen yet\" (issue #829) — honest absence, never `0` and never a placeholder.
  @BuiltValueField(wireName: r'block_number')
  int? get blockNumber;

  /// The season the imported rows land in (the owning season of the job's block, or the declared season of a block-less upload).
  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  /// The season's production-global number.
  @BuiltValueField(wireName: r'season_number')
  int get seasonNumber;

  AiImportTarget._();

  factory AiImportTarget([void updates(AiImportTargetBuilder b)]) =
      _$AiImportTarget;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportTargetBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportTarget> get serializer =>
      _$AiImportTargetSerializer();
}

class _$AiImportTargetSerializer
    implements PrimitiveSerializer<AiImportTarget> {
  @override
  final Iterable<Type> types = const [AiImportTarget, _$AiImportTarget];

  @override
  final String wireName = r'AiImportTarget';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportTarget object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.blockNumber != null) {
      yield r'block_number';
      yield serializers.serialize(
        object.blockNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'season_id';
    yield serializers.serialize(
      object.seasonId,
      specifiedType: const FullType(String),
    );
    yield r'season_number';
    yield serializers.serialize(
      object.seasonNumber,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiImportTarget object, {
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
    required AiImportTargetBuilder result,
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
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seasonId = valueDes;
          break;
        case r'season_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.seasonNumber = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiImportTarget deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportTargetBuilder();
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
