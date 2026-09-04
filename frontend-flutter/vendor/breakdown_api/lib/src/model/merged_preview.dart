// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/shooting_schedule_row.dart';
import 'package:breakdown_api/src/model/merged_scene.dart';
import 'package:breakdown_api/src/model/scene_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'merged_preview.g.dart';

/// MergedPreview
///
/// Properties:
/// * [scenes]
/// * [unmatchedScheduleRows]
/// * [unmatchedScriptScenes]
@BuiltValue()
abstract class MergedPreview
    implements Built<MergedPreview, MergedPreviewBuilder> {
  @BuiltValueField(wireName: r'scenes')
  BuiltList<MergedScene> get scenes;

  @BuiltValueField(wireName: r'unmatched_schedule_rows')
  BuiltList<ShootingScheduleRow> get unmatchedScheduleRows;

  @BuiltValueField(wireName: r'unmatched_script_scenes')
  BuiltList<SceneView> get unmatchedScriptScenes;

  MergedPreview._();

  factory MergedPreview([void updates(MergedPreviewBuilder b)]) =
      _$MergedPreview;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MergedPreviewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MergedPreview> get serializer =>
      _$MergedPreviewSerializer();
}

class _$MergedPreviewSerializer implements PrimitiveSerializer<MergedPreview> {
  @override
  final Iterable<Type> types = const [MergedPreview, _$MergedPreview];

  @override
  final String wireName = r'MergedPreview';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MergedPreview object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'scenes';
    yield serializers.serialize(
      object.scenes,
      specifiedType: const FullType(BuiltList, [FullType(MergedScene)]),
    );
    yield r'unmatched_schedule_rows';
    yield serializers.serialize(
      object.unmatchedScheduleRows,
      specifiedType: const FullType(BuiltList, [FullType(ShootingScheduleRow)]),
    );
    yield r'unmatched_script_scenes';
    yield serializers.serialize(
      object.unmatchedScriptScenes,
      specifiedType: const FullType(BuiltList, [FullType(SceneView)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MergedPreview object, {
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
    required MergedPreviewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'scenes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(MergedScene)]),
          ) as BuiltList<MergedScene>;
          result.scenes.replace(valueDes);
          break;
        case r'unmatched_schedule_rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ShootingScheduleRow)]),
          ) as BuiltList<ShootingScheduleRow>;
          result.unmatchedScheduleRows.replace(valueDes);
          break;
        case r'unmatched_script_scenes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(SceneView)]),
          ) as BuiltList<SceneView>;
          result.unmatchedScriptScenes.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MergedPreview deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MergedPreviewBuilder();
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
