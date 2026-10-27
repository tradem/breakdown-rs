// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_piece_request.g.dart';

/// Create-piece payload.  `name` is required (a fundus garment without a name is unreachable for the wardrobe crew). `category_id` is the optional single category — the API edge pre-checks the season invariant (`category.season_id ∈ piece.seasons`). `season_id` is the optional initial repertoire season; the API edge resolves the `project_id` audit metadata from the season projection (404 on an unknown season).
///
/// Properties:
/// * [categoryId]
/// * [name]
/// * [seasonId] - Opaque identifier for a `Season` aggregate.
@BuiltValue()
abstract class CreatePieceRequest
    implements Built<CreatePieceRequest, CreatePieceRequestBuilder> {
  @BuiltValueField(wireName: r'category_id')
  String? get categoryId;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// Opaque identifier for a `Season` aggregate.
  @BuiltValueField(wireName: r'season_id')
  String? get seasonId;

  CreatePieceRequest._();

  factory CreatePieceRequest([void updates(CreatePieceRequestBuilder b)]) =
      _$CreatePieceRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreatePieceRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreatePieceRequest> get serializer =>
      _$CreatePieceRequestSerializer();
}

class _$CreatePieceRequestSerializer
    implements PrimitiveSerializer<CreatePieceRequest> {
  @override
  final Iterable<Type> types = const [CreatePieceRequest, _$CreatePieceRequest];

  @override
  final String wireName = r'CreatePieceRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreatePieceRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.categoryId != null) {
      yield r'category_id';
      yield serializers.serialize(
        object.categoryId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
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
    CreatePieceRequest object, {
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
    required CreatePieceRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.categoryId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
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
  CreatePieceRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreatePieceRequestBuilder();
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
