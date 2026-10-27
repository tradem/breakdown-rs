// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/piece_detail_request.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_piece_detail_request.g.dart';

/// AddPieceDetailRequest
///
/// Properties:
/// * [detail]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class AddPieceDetailRequest
    implements Built<AddPieceDetailRequest, AddPieceDetailRequestBuilder> {
  @BuiltValueField(wireName: r'detail')
  PieceDetailRequest get detail;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  AddPieceDetailRequest._();

  factory AddPieceDetailRequest(
      [void updates(AddPieceDetailRequestBuilder b)]) = _$AddPieceDetailRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddPieceDetailRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddPieceDetailRequest> get serializer =>
      _$AddPieceDetailRequestSerializer();
}

class _$AddPieceDetailRequestSerializer
    implements PrimitiveSerializer<AddPieceDetailRequest> {
  @override
  final Iterable<Type> types = const [
    AddPieceDetailRequest,
    _$AddPieceDetailRequest
  ];

  @override
  final String wireName = r'AddPieceDetailRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddPieceDetailRequest object, {
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
    AddPieceDetailRequest object, {
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
    required AddPieceDetailRequestBuilder result,
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
  AddPieceDetailRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddPieceDetailRequestBuilder();
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
