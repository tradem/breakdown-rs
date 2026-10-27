// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/appearance_outfit_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'character_appearance_view.g.dart';

/// One appearance of a character in a scene (issue #621): the scene reference in script order plus the character's own outfit beats in that scene.  Backs `GET /v1/characters/{id}/appearances` — the role extract (\"Ring binder per role\"): every scene the character appears in, in `scene_number` order, with the outfit(s) that character wears there.
///
/// Properties:
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
/// * [outfits] - The character's outfit beats in this scene, ordered by `order`. Empty when the character has no outfit beat in the scene yet.
/// * [sceneId]
/// * [sceneNumber] - Script-order scene number; `None` for scenes not yet numbered.
/// * [synopsis] - Scene synopsis (the scene projection's `summary`), for the extract row.
@BuiltValue()
abstract class CharacterAppearanceView
    implements Built<CharacterAppearanceView, CharacterAppearanceViewBuilder> {
  /// Opaque identifier for an `Episode` aggregate.
  @BuiltValueField(wireName: r'episode_id')
  String get episodeId;

  /// The character's outfit beats in this scene, ordered by `order`. Empty when the character has no outfit beat in the scene yet.
  @BuiltValueField(wireName: r'outfits')
  BuiltList<AppearanceOutfitView>? get outfits;

  @BuiltValueField(wireName: r'scene_id')
  String get sceneId;

  /// Script-order scene number; `None` for scenes not yet numbered.
  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  /// Scene synopsis (the scene projection's `summary`), for the extract row.
  @BuiltValueField(wireName: r'synopsis')
  String? get synopsis;

  CharacterAppearanceView._();

  factory CharacterAppearanceView(
          [void updates(CharacterAppearanceViewBuilder b)]) =
      _$CharacterAppearanceView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CharacterAppearanceViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CharacterAppearanceView> get serializer =>
      _$CharacterAppearanceViewSerializer();
}

class _$CharacterAppearanceViewSerializer
    implements PrimitiveSerializer<CharacterAppearanceView> {
  @override
  final Iterable<Type> types = const [
    CharacterAppearanceView,
    _$CharacterAppearanceView
  ];

  @override
  final String wireName = r'CharacterAppearanceView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CharacterAppearanceView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'episode_id';
    yield serializers.serialize(
      object.episodeId,
      specifiedType: const FullType(String),
    );
    if (object.outfits != null) {
      yield r'outfits';
      yield serializers.serialize(
        object.outfits,
        specifiedType:
            const FullType(BuiltList, [FullType(AppearanceOutfitView)]),
      );
    }
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
    if (object.synopsis != null) {
      yield r'synopsis';
      yield serializers.serialize(
        object.synopsis,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CharacterAppearanceView object, {
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
    required CharacterAppearanceViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'episode_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeId = valueDes;
          break;
        case r'outfits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(
                BuiltList, [FullType(AppearanceOutfitView)]),
          ) as BuiltList<AppearanceOutfitView>?;
          if (valueDes == null) continue;
          result.outfits.replace(valueDes);
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
        case r'synopsis':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.synopsis = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CharacterAppearanceView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CharacterAppearanceViewBuilder();
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
