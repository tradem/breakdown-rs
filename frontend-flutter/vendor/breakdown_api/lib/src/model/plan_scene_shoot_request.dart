// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'plan_scene_shoot_request.g.dart';

/// PlanSceneShootRequest
///
/// Properties:
/// * [plannedOrder] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [sceneId]
/// * [shootingDayId] - Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
@BuiltValue()
abstract class PlanSceneShootRequest
    implements Built<PlanSceneShootRequest, PlanSceneShootRequestBuilder> {
  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'planned_order')
  String get plannedOrder;

  @BuiltValueField(wireName: r'scene_id')
  String get sceneId;

  /// Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
  @BuiltValueField(wireName: r'shooting_day_id')
  String get shootingDayId;

  PlanSceneShootRequest._();

  factory PlanSceneShootRequest(
      [void updates(PlanSceneShootRequestBuilder b)]) = _$PlanSceneShootRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PlanSceneShootRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PlanSceneShootRequest> get serializer =>
      _$PlanSceneShootRequestSerializer();
}

class _$PlanSceneShootRequestSerializer
    implements PrimitiveSerializer<PlanSceneShootRequest> {
  @override
  final Iterable<Type> types = const [
    PlanSceneShootRequest,
    _$PlanSceneShootRequest
  ];

  @override
  final String wireName = r'PlanSceneShootRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PlanSceneShootRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'planned_order';
    yield serializers.serialize(
      object.plannedOrder,
      specifiedType: const FullType(String),
    );
    yield r'scene_id';
    yield serializers.serialize(
      object.sceneId,
      specifiedType: const FullType(String),
    );
    yield r'shooting_day_id';
    yield serializers.serialize(
      object.shootingDayId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PlanSceneShootRequest object, {
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
    required PlanSceneShootRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'planned_order':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.plannedOrder = valueDes;
          break;
        case r'scene_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sceneId = valueDes;
          break;
        case r'shooting_day_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.shootingDayId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PlanSceneShootRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PlanSceneShootRequestBuilder();
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
