// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/serialized_note.dart';
import 'package:breakdown_api/src/model/scene_shoot_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_shoot_view.g.dart';

/// Complete scene-shoot read model.  `updated_at` is sourced from the timestamp of the last applied `SceneShootEvent`, not from the UUIDv7 event id.
///
/// Properties:
/// * [actualOrder] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [continuityPhotoIds]
/// * [endDt]
/// * [id] - Opaque identifier for a `SceneShoot` aggregate.  A `SceneShoot` models the association between a `Scene` and a `ShootingDay`, carrying both planned and actual execution data. Each `(scene_id, shooting_day_id)` pair gets its own stream. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`.
/// * [notes]
/// * [plannedOrder] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [sceneId]
/// * [shootingDayId] - Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
/// * [startDt]
/// * [status]
/// * [updatedAt]
/// * [version] - Aggregate version of the last applied event; echo back in optimistic-locking commands.
@BuiltValue()
abstract class SceneShootView
    implements Built<SceneShootView, SceneShootViewBuilder> {
  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'actual_order')
  String? get actualOrder;

  @BuiltValueField(wireName: r'continuity_photo_ids')
  BuiltList<String> get continuityPhotoIds;

  @BuiltValueField(wireName: r'end_dt')
  DateTime? get endDt;

  /// Opaque identifier for a `SceneShoot` aggregate.  A `SceneShoot` models the association between a `Scene` and a `ShootingDay`, carrying both planned and actual execution data. Each `(scene_id, shooting_day_id)` pair gets its own stream. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`.
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'notes')
  BuiltList<SerializedNote> get notes;

  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'planned_order')
  String get plannedOrder;

  @BuiltValueField(wireName: r'scene_id')
  String get sceneId;

  /// Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
  @BuiltValueField(wireName: r'shooting_day_id')
  String get shootingDayId;

  @BuiltValueField(wireName: r'start_dt')
  DateTime? get startDt;

  @BuiltValueField(wireName: r'status')
  SceneShootStatus get status;
  // enum statusEnum {  Planned,  Scheduled,  InProgress,  Shot,  Skipped,  };

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
  @BuiltValueField(wireName: r'version')
  int get version;

  SceneShootView._();

  factory SceneShootView([void updates(SceneShootViewBuilder b)]) =
      _$SceneShootView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneShootViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneShootView> get serializer =>
      _$SceneShootViewSerializer();
}

class _$SceneShootViewSerializer
    implements PrimitiveSerializer<SceneShootView> {
  @override
  final Iterable<Type> types = const [SceneShootView, _$SceneShootView];

  @override
  final String wireName = r'SceneShootView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneShootView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.actualOrder != null) {
      yield r'actual_order';
      yield serializers.serialize(
        object.actualOrder,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'continuity_photo_ids';
    yield serializers.serialize(
      object.continuityPhotoIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.endDt != null) {
      yield r'end_dt';
      yield serializers.serialize(
        object.endDt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'notes';
    yield serializers.serialize(
      object.notes,
      specifiedType: const FullType(BuiltList, [FullType(SerializedNote)]),
    );
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
    if (object.startDt != null) {
      yield r'start_dt';
      yield serializers.serialize(
        object.startDt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(SceneShootStatus),
    );
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
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
    SceneShootView object, {
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
    required SceneShootViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'actual_order':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.actualOrder = valueDes;
          break;
        case r'continuity_photo_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.continuityPhotoIds.replace(valueDes);
          break;
        case r'end_dt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.endDt = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(SerializedNote)]),
          ) as BuiltList<SerializedNote>;
          result.notes.replace(valueDes);
          break;
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
        case r'start_dt':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.startDt = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SceneShootStatus),
          ) as SceneShootStatus;
          result.status = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
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
  SceneShootView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneShootViewBuilder();
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
