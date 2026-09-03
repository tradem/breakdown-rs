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

part 'shoot_day_row.g.dart';

/// A single row in the Shoot Day (execution / Ist) report.
///
/// Properties:
/// * [actualOrder] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [continuityPhotoIds]
/// * [endDt]
/// * [location]
/// * [notes]
/// * [sceneId]
/// * [sceneNumber]
/// * [scriptDay]
/// * [startDt]
/// * [status]
@BuiltValue()
abstract class ShootDayRow implements Built<ShootDayRow, ShootDayRowBuilder> {
  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'actual_order')
  String? get actualOrder;

  @BuiltValueField(wireName: r'continuity_photo_ids')
  BuiltList<String> get continuityPhotoIds;

  @BuiltValueField(wireName: r'end_dt')
  DateTime? get endDt;

  @BuiltValueField(wireName: r'location')
  String? get location;

  @BuiltValueField(wireName: r'notes')
  BuiltList<SerializedNote> get notes;

  @BuiltValueField(wireName: r'scene_id')
  String get sceneId;

  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  @BuiltValueField(wireName: r'script_day')
  String? get scriptDay;

  @BuiltValueField(wireName: r'start_dt')
  DateTime? get startDt;

  @BuiltValueField(wireName: r'status')
  SceneShootStatus get status;
  // enum statusEnum {  Planned,  Scheduled,  InProgress,  Shot,  Skipped,  };

  ShootDayRow._();

  factory ShootDayRow([void updates(ShootDayRowBuilder b)]) = _$ShootDayRow;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShootDayRowBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShootDayRow> get serializer => _$ShootDayRowSerializer();
}

class _$ShootDayRowSerializer implements PrimitiveSerializer<ShootDayRow> {
  @override
  final Iterable<Type> types = const [ShootDayRow, _$ShootDayRow];

  @override
  final String wireName = r'ShootDayRow';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShootDayRow object, {
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
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'notes';
    yield serializers.serialize(
      object.notes,
      specifiedType: const FullType(BuiltList, [FullType(SerializedNote)]),
    );
    yield r'scene_id';
    yield serializers.serialize(
      object.sceneId,
      specifiedType: const FullType(String),
    );
    if (object.sceneNumber != null) {
      yield r'scene_number';
      yield serializers.serialize(
        object.sceneNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.scriptDay != null) {
      yield r'script_day';
      yield serializers.serialize(
        object.scriptDay,
        specifiedType: const FullType.nullable(String),
      );
    }
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
  }

  @override
  Object serialize(
    Serializers serializers,
    ShootDayRow object, {
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
    required ShootDayRowBuilder result,
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
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.location = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(SerializedNote)]),
          ) as BuiltList<SerializedNote>;
          result.notes.replace(valueDes);
          break;
        case r'scene_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sceneId = valueDes;
          break;
        case r'scene_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sceneNumber = valueDes;
          break;
        case r'script_day':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.scriptDay = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ShootDayRow deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShootDayRowBuilder();
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
