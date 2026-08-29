// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_costume_category_request.g.dart';

/// UpdateCostumeCategoryRequest
///
/// Properties:
/// * [name]
/// * [orderKey] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdateCostumeCategoryRequest
    implements
        Built<UpdateCostumeCategoryRequest,
            UpdateCostumeCategoryRequestBuilder> {
  @BuiltValueField(wireName: r'name')
  String? get name;

  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'order_key')
  String? get orderKey;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdateCostumeCategoryRequest._();

  factory UpdateCostumeCategoryRequest(
          [void updates(UpdateCostumeCategoryRequestBuilder b)]) =
      _$UpdateCostumeCategoryRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateCostumeCategoryRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateCostumeCategoryRequest> get serializer =>
      _$UpdateCostumeCategoryRequestSerializer();
}

class _$UpdateCostumeCategoryRequestSerializer
    implements PrimitiveSerializer<UpdateCostumeCategoryRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateCostumeCategoryRequest,
    _$UpdateCostumeCategoryRequest
  ];

  @override
  final String wireName = r'UpdateCostumeCategoryRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateCostumeCategoryRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.orderKey != null) {
      yield r'order_key';
      yield serializers.serialize(
        object.orderKey,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateCostumeCategoryRequest object, {
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
    required UpdateCostumeCategoryRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'order_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.orderKey = valueDes;
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
  UpdateCostumeCategoryRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateCostumeCategoryRequestBuilder();
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
