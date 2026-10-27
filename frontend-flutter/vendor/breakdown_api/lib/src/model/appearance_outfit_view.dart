// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appearance_outfit_view.g.dart';

/// One outfit beat of a character within one scene (issue #621): the character-scoped slice of `projection_scene_outfit_assignment`, enriched by join with `projection_outfit` for the look's name and variant lineage.
///
/// Properties:
/// * [note] - Optional free-text cue for the wardrobe crew.
/// * [order] - Dense, zero-based, unique per character within this scene.
/// * [outfitId]
/// * [outfitName]
/// * [variantOf]
@BuiltValue()
abstract class AppearanceOutfitView
    implements Built<AppearanceOutfitView, AppearanceOutfitViewBuilder> {
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

  AppearanceOutfitView._();

  factory AppearanceOutfitView([void updates(AppearanceOutfitViewBuilder b)]) =
      _$AppearanceOutfitView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppearanceOutfitViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppearanceOutfitView> get serializer =>
      _$AppearanceOutfitViewSerializer();
}

class _$AppearanceOutfitViewSerializer
    implements PrimitiveSerializer<AppearanceOutfitView> {
  @override
  final Iterable<Type> types = const [
    AppearanceOutfitView,
    _$AppearanceOutfitView
  ];

  @override
  final String wireName = r'AppearanceOutfitView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppearanceOutfitView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    AppearanceOutfitView object, {
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
    required AppearanceOutfitViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  AppearanceOutfitView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppearanceOutfitViewBuilder();
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
