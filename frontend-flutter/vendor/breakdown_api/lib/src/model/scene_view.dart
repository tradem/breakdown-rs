// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_view.g.dart';

/// Complete scene read model.  `updated_at` is sourced from the timestamp of the last applied `SceneEvent`, not from the UUIDv7 event id (ADR-004 + ADR-015).
///
/// Properties:
/// * [assignedCharacters]
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
/// * [id]
/// * [isScheduleSet]
/// * [location]
/// * [mood]
/// * [sceneNumber]
/// * [scriptDay] - Fictional script-chronology day (e.g. \"1. Spieltag\"), distinct from the calendar `ShootingDay.date`.
/// * [shootingDayIds] - Shooting days this scene is scheduled on.
/// * [summary]
/// * [updatedAt]
/// * [version] - Aggregate version of the last applied event; echo back in optimistic-locking commands.
@BuiltValue()
abstract class SceneView implements Built<SceneView, SceneViewBuilder> {
  @BuiltValueField(wireName: r'assigned_characters')
  BuiltList<String> get assignedCharacters;

  /// Opaque identifier for an `Episode` aggregate.
  @BuiltValueField(wireName: r'episode_id')
  String get episodeId;

  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'is_schedule_set')
  bool get isScheduleSet;

  @BuiltValueField(wireName: r'location')
  String? get location;

  @BuiltValueField(wireName: r'mood')
  String? get mood;

  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  /// Fictional script-chronology day (e.g. \"1. Spieltag\"), distinct from the calendar `ShootingDay.date`.
  @BuiltValueField(wireName: r'script_day')
  String? get scriptDay;

  /// Shooting days this scene is scheduled on.
  @BuiltValueField(wireName: r'shooting_day_ids')
  BuiltList<String> get shootingDayIds;

  @BuiltValueField(wireName: r'summary')
  String? get summary;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
  @BuiltValueField(wireName: r'version')
  int get version;

  SceneView._();

  factory SceneView([void updates(SceneViewBuilder b)]) = _$SceneView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneView> get serializer => _$SceneViewSerializer();
}

class _$SceneViewSerializer implements PrimitiveSerializer<SceneView> {
  @override
  final Iterable<Type> types = const [SceneView, _$SceneView];

  @override
  final String wireName = r'SceneView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'assigned_characters';
    yield serializers.serialize(
      object.assignedCharacters,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'episode_id';
    yield serializers.serialize(
      object.episodeId,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'is_schedule_set';
    yield serializers.serialize(
      object.isScheduleSet,
      specifiedType: const FullType(bool),
    );
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.mood != null) {
      yield r'mood';
      yield serializers.serialize(
        object.mood,
        specifiedType: const FullType.nullable(String),
      );
    }
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
    yield r'shooting_day_ids';
    yield serializers.serialize(
      object.shootingDayIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    if (object.summary != null) {
      yield r'summary';
      yield serializers.serialize(
        object.summary,
        specifiedType: const FullType.nullable(String),
      );
    }
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
    SceneView object, {
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
    required SceneViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'assigned_characters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.assignedCharacters.replace(valueDes);
          break;
        case r'episode_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeId = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'is_schedule_set':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isScheduleSet = valueDes;
          break;
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.location = valueDes;
          break;
        case r'mood':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.mood = valueDes;
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
        case r'shooting_day_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.shootingDayIds.replace(valueDes);
          break;
        case r'summary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.summary = valueDes;
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
  SceneView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneViewBuilder();
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
