// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_costume_request.g.dart';

/// Create-costume payload (issue #453).  `season_id` is the optional repertoire season: when present, the costume joins that season's costume stream while unassigned. The API edge resolves the `series_id` audit metadata from the season projection (404 on an unknown season).
///
/// Properties:
/// * [seasonId] - Opaque identifier for a `Season` aggregate.
@BuiltValue()
abstract class CreateCostumeRequest
    implements Built<CreateCostumeRequest, CreateCostumeRequestBuilder> {
  /// Opaque identifier for a `Season` aggregate.
  @BuiltValueField(wireName: r'season_id')
  String? get seasonId;

  CreateCostumeRequest._();

  factory CreateCostumeRequest([void updates(CreateCostumeRequestBuilder b)]) =
      _$CreateCostumeRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateCostumeRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateCostumeRequest> get serializer =>
      _$CreateCostumeRequestSerializer();
}

class _$CreateCostumeRequestSerializer
    implements PrimitiveSerializer<CreateCostumeRequest> {
  @override
  final Iterable<Type> types = const [
    CreateCostumeRequest,
    _$CreateCostumeRequest
  ];

  @override
  final String wireName = r'CreateCostumeRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateCostumeRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.seasonId != null) {
      yield r'season_id';
      yield serializers.serialize(
        object.seasonId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateCostumeRequest object, {
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
    required CreateCostumeRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.seasonId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateCostumeRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateCostumeRequestBuilder();
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
