// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/piece_detail_request.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_piece_detail_request.g.dart';

/// Replace an existing piece detail in full (issue #544).  The body carries the **whole** detail, not a patch: a patch-merge would leave the field merging to the client and make an emptied `subject` ambiguous (cleared on purpose vs. lost). `detail.id` must equal the `detail_id` path parameter — the aggregate validates the id against its state and answers 404 `piece-detail.not-found` without emitting an event when the detail is unknown.
///
/// Properties:
/// * [detail]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdatePieceDetailRequest
    implements
        Built<UpdatePieceDetailRequest, UpdatePieceDetailRequestBuilder> {
  @BuiltValueField(wireName: r'detail')
  PieceDetailRequest get detail;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdatePieceDetailRequest._();

  factory UpdatePieceDetailRequest(
          [void updates(UpdatePieceDetailRequestBuilder b)]) =
      _$UpdatePieceDetailRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdatePieceDetailRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdatePieceDetailRequest> get serializer =>
      _$UpdatePieceDetailRequestSerializer();
}

class _$UpdatePieceDetailRequestSerializer
    implements PrimitiveSerializer<UpdatePieceDetailRequest> {
  @override
  final Iterable<Type> types = const [
    UpdatePieceDetailRequest,
    _$UpdatePieceDetailRequest
  ];

  @override
  final String wireName = r'UpdatePieceDetailRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdatePieceDetailRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'detail';
    yield serializers.serialize(
      object.detail,
      specifiedType: const FullType(PieceDetailRequest),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdatePieceDetailRequest object, {
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
    required UpdatePieceDetailRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PieceDetailRequest),
          ) as PieceDetailRequest;
          result.detail.replace(valueDes);
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdatePieceDetailRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdatePieceDetailRequestBuilder();
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
