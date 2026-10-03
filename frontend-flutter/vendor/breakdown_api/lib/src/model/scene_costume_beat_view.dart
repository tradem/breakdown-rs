// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_costume_beat_view.g.dart';

/// One costume beat of a scene, enriched by the query layer: character and costume identity resolved by join (`projection_character`, `projection_costume`); a projection miss yields `None`, never an error (audit/derived metadata never blocks reads, issue #546).
///
/// Properties:
/// * [characterId]
/// * [characterName]
/// * [costumeCategoryId]
/// * [costumeCategoryName]
/// * [costumeId]
/// * [note] - Optional free-text cue for the wardrobe crew.
/// * [order] - Dense, zero-based, unique per character within this scene.
@BuiltValue()
abstract class SceneCostumeBeatView
    implements Built<SceneCostumeBeatView, SceneCostumeBeatViewBuilder> {
  @BuiltValueField(wireName: r'character_id')
  String get characterId;

  @BuiltValueField(wireName: r'character_name')
  String? get characterName;

  @BuiltValueField(wireName: r'costume_category_id')
  String? get costumeCategoryId;

  @BuiltValueField(wireName: r'costume_category_name')
  String? get costumeCategoryName;

  @BuiltValueField(wireName: r'costume_id')
  String get costumeId;

  /// Optional free-text cue for the wardrobe crew.
  @BuiltValueField(wireName: r'note')
  String? get note;

  /// Dense, zero-based, unique per character within this scene.
  @BuiltValueField(wireName: r'order')
  int get order;

  SceneCostumeBeatView._();

  factory SceneCostumeBeatView([void updates(SceneCostumeBeatViewBuilder b)]) =
      _$SceneCostumeBeatView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneCostumeBeatViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneCostumeBeatView> get serializer =>
      _$SceneCostumeBeatViewSerializer();
}

class _$SceneCostumeBeatViewSerializer
    implements PrimitiveSerializer<SceneCostumeBeatView> {
  @override
  final Iterable<Type> types = const [
    SceneCostumeBeatView,
    _$SceneCostumeBeatView
  ];

  @override
  final String wireName = r'SceneCostumeBeatView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneCostumeBeatView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_id';
    yield serializers.serialize(
      object.characterId,
      specifiedType: const FullType(String),
    );
    if (object.characterName != null) {
      yield r'character_name';
      yield serializers.serialize(
        object.characterName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.costumeCategoryId != null) {
      yield r'costume_category_id';
      yield serializers.serialize(
        object.costumeCategoryId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.costumeCategoryName != null) {
      yield r'costume_category_name';
      yield serializers.serialize(
        object.costumeCategoryName,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'costume_id';
    yield serializers.serialize(
      object.costumeId,
      specifiedType: const FullType(String),
    );
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'order';
    yield serializers.serialize(
      object.order,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneCostumeBeatView object, {
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
    required SceneCostumeBeatViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterId = valueDes;
          break;
        case r'character_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.characterName = valueDes;
          break;
        case r'costume_category_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.costumeCategoryId = valueDes;
          break;
        case r'costume_category_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.costumeCategoryName = valueDes;
          break;
        case r'costume_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.costumeId = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.note = valueDes;
          break;
        case r'order':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.order = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneCostumeBeatView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneCostumeBeatViewBuilder();
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
