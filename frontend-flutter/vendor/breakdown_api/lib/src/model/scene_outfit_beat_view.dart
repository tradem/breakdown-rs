// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_outfit_beat_view.g.dart';

/// One outfit beat of a scene, enriched by the query layer: character and outfit identity resolved by join (`projection_character`, `projection_outfit`); a projection miss yields `None`, never an error (audit/derived metadata never blocks reads, issue #546).
///
/// Properties:
/// * [characterId]
/// * [characterName]
/// * [note] - Optional free-text cue for the wardrobe crew.
/// * [order] - Dense, zero-based, unique per character within this scene.
/// * [outfitId]
/// * [outfitName]
/// * [variantOf]
@BuiltValue()
abstract class SceneOutfitBeatView
    implements Built<SceneOutfitBeatView, SceneOutfitBeatViewBuilder> {
  @BuiltValueField(wireName: r'character_id')
  String get characterId;

  @BuiltValueField(wireName: r'character_name')
  String? get characterName;

  /// Optional free-text cue for the wardrobe crew.
  @BuiltValueField(wireName: r'note')
  String? get note;

  /// Dense, zero-based, unique per character within this scene.
  @BuiltValueField(wireName: r'order')
  int get order;

  @BuiltValueField(wireName: r'outfit_id')
  String get outfitId;

  @BuiltValueField(wireName: r'outfit_name')
  String? get outfitName;

  @BuiltValueField(wireName: r'variant_of')
  String? get variantOf;

  SceneOutfitBeatView._();

  factory SceneOutfitBeatView([void updates(SceneOutfitBeatViewBuilder b)]) =
      _$SceneOutfitBeatView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneOutfitBeatViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneOutfitBeatView> get serializer =>
      _$SceneOutfitBeatViewSerializer();
}

class _$SceneOutfitBeatViewSerializer
    implements PrimitiveSerializer<SceneOutfitBeatView> {
  @override
  final Iterable<Type> types = const [
    SceneOutfitBeatView,
    _$SceneOutfitBeatView
  ];

  @override
  final String wireName = r'SceneOutfitBeatView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneOutfitBeatView object, {
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
    yield r'outfit_id';
    yield serializers.serialize(
      object.outfitId,
      specifiedType: const FullType(String),
    );
    if (object.outfitName != null) {
      yield r'outfit_name';
      yield serializers.serialize(
        object.outfitName,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.variantOf != null) {
      yield r'variant_of';
      yield serializers.serialize(
        object.variantOf,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneOutfitBeatView object, {
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
    required SceneOutfitBeatViewBuilder result,
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
        case r'outfit_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.outfitId = valueDes;
          break;
        case r'outfit_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.outfitName = valueDes;
          break;
        case r'variant_of':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.variantOf = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneOutfitBeatView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneOutfitBeatViewBuilder();
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
