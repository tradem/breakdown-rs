// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/costume_detail_request.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_costume_detail_request.g.dart';

/// Replace an existing costume detail in full (issue #544).  The body carries the **whole** detail, not a patch: a patch-merge would leave the field merging to the client and make an emptied `subject` ambiguous (cleared on purpose vs. lost). `detail.id` must equal the `detail_id` path parameter — the aggregate validates the id against its state and answers 404 `costume-detail.not-found` without emitting an event when the detail is unknown.
///
/// Properties:
/// * [detail]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdateCostumeDetailRequest
    implements
        Built<UpdateCostumeDetailRequest, UpdateCostumeDetailRequestBuilder> {
  @BuiltValueField(wireName: r'detail')
  CostumeDetailRequest get detail;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdateCostumeDetailRequest._();

  factory UpdateCostumeDetailRequest(
          [void updates(UpdateCostumeDetailRequestBuilder b)]) =
      _$UpdateCostumeDetailRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateCostumeDetailRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateCostumeDetailRequest> get serializer =>
      _$UpdateCostumeDetailRequestSerializer();
}

class _$UpdateCostumeDetailRequestSerializer
    implements PrimitiveSerializer<UpdateCostumeDetailRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateCostumeDetailRequest,
    _$UpdateCostumeDetailRequest
  ];

  @override
  final String wireName = r'UpdateCostumeDetailRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateCostumeDetailRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'detail';
    yield serializers.serialize(
      object.detail,
      specifiedType: const FullType(CostumeDetailRequest),
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
    UpdateCostumeDetailRequest object, {
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
    required UpdateCostumeDetailRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CostumeDetailRequest),
          ) as CostumeDetailRequest;
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
  UpdateCostumeDetailRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateCostumeDetailRequestBuilder();
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
