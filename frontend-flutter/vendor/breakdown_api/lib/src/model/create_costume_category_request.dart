// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_costume_category_request.g.dart';

/// CreateCostumeCategoryRequest
///
/// Properties:
/// * [name]
/// * [orderKey] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [seasonId] - Opaque identifier for a `Season` aggregate.
@BuiltValue()
abstract class CreateCostumeCategoryRequest
    implements
        Built<CreateCostumeCategoryRequest,
            CreateCostumeCategoryRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String get name;

  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'order_key')
  String get orderKey;

  /// Opaque identifier for a `Season` aggregate.
  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  CreateCostumeCategoryRequest._();

  factory CreateCostumeCategoryRequest(
          [void updates(CreateCostumeCategoryRequestBuilder b)]) =
      _$CreateCostumeCategoryRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateCostumeCategoryRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateCostumeCategoryRequest> get serializer =>
      _$CreateCostumeCategoryRequestSerializer();
}

class _$CreateCostumeCategoryRequestSerializer
    implements PrimitiveSerializer<CreateCostumeCategoryRequest> {
  @override
  final Iterable<Type> types = const [
    CreateCostumeCategoryRequest,
    _$CreateCostumeCategoryRequest
  ];

  @override
  final String wireName = r'CreateCostumeCategoryRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateCostumeCategoryRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'order_key';
    yield serializers.serialize(
      object.orderKey,
      specifiedType: const FullType(String),
    );
    yield r'season_id';
    yield serializers.serialize(
      object.seasonId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateCostumeCategoryRequest object, {
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
    required CreateCostumeCategoryRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'order_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.orderKey = valueDes;
          break;
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
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
  CreateCostumeCategoryRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateCostumeCategoryRequestBuilder();
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
