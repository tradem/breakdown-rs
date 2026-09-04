// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/shooting_schedule_row.dart';
import 'package:breakdown_api/src/model/scene_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'merged_scene.g.dart';

/// MergedScene
///
/// Properties:
/// * [scene]
/// * [scheduleRows]
@BuiltValue()
abstract class MergedScene implements Built<MergedScene, MergedSceneBuilder> {
  @BuiltValueField(wireName: r'scene')
  SceneView get scene;

  @BuiltValueField(wireName: r'schedule_rows')
  BuiltList<ShootingScheduleRow> get scheduleRows;

  MergedScene._();

  factory MergedScene([void updates(MergedSceneBuilder b)]) = _$MergedScene;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MergedSceneBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MergedScene> get serializer => _$MergedSceneSerializer();
}

class _$MergedSceneSerializer implements PrimitiveSerializer<MergedScene> {
  @override
  final Iterable<Type> types = const [MergedScene, _$MergedScene];

  @override
  final String wireName = r'MergedScene';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MergedScene object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'scene';
    yield serializers.serialize(
      object.scene,
      specifiedType: const FullType(SceneView),
    );
    yield r'schedule_rows';
    yield serializers.serialize(
      object.scheduleRows,
      specifiedType: const FullType(BuiltList, [FullType(ShootingScheduleRow)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MergedScene object, {
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
    required MergedSceneBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'scene':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SceneView),
          ) as SceneView;
          result.scene.replace(valueDes);
          break;
        case r'schedule_rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ShootingScheduleRow)]),
          ) as BuiltList<ShootingScheduleRow>;
          result.scheduleRows.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MergedScene deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MergedSceneBuilder();
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
