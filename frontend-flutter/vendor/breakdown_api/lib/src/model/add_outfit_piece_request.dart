// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_outfit_piece_request.g.dart';

/// AddOutfitPieceRequest
///
/// Properties:
/// * [pieceId]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class AddOutfitPieceRequest
    implements Built<AddOutfitPieceRequest, AddOutfitPieceRequestBuilder> {
  @BuiltValueField(wireName: r'piece_id')
  String get pieceId;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  AddOutfitPieceRequest._();

  factory AddOutfitPieceRequest(
      [void updates(AddOutfitPieceRequestBuilder b)]) = _$AddOutfitPieceRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddOutfitPieceRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddOutfitPieceRequest> get serializer =>
      _$AddOutfitPieceRequestSerializer();
}

class _$AddOutfitPieceRequestSerializer
    implements PrimitiveSerializer<AddOutfitPieceRequest> {
  @override
  final Iterable<Type> types = const [
    AddOutfitPieceRequest,
    _$AddOutfitPieceRequest
  ];

  @override
  final String wireName = r'AddOutfitPieceRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddOutfitPieceRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'piece_id';
    yield serializers.serialize(
      object.pieceId,
      specifiedType: const FullType(String),
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
    AddOutfitPieceRequest object, {
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
    required AddOutfitPieceRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'piece_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.pieceId = valueDes;
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
  AddOutfitPieceRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddOutfitPieceRequestBuilder();
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
