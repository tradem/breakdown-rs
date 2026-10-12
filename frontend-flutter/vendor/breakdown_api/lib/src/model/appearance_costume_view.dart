// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'appearance_costume_view.g.dart';

/// One costume beat of a character within one scene (issue #621): the character-scoped slice of `projection_scene_costume_assignment`, enriched by join with `projection_costume` for the category.
///
/// Properties:
/// * [costumeCategoryId]
/// * [costumeCategoryName]
/// * [costumeId]
/// * [note] - Optional free-text cue for the wardrobe crew.
/// * [order] - Dense, zero-based, unique per character within this scene.
@BuiltValue()
abstract class AppearanceCostumeView
    implements Built<AppearanceCostumeView, AppearanceCostumeViewBuilder> {
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

  AppearanceCostumeView._();

  factory AppearanceCostumeView(
      [void updates(AppearanceCostumeViewBuilder b)]) = _$AppearanceCostumeView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AppearanceCostumeViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AppearanceCostumeView> get serializer =>
      _$AppearanceCostumeViewSerializer();
}

class _$AppearanceCostumeViewSerializer
    implements PrimitiveSerializer<AppearanceCostumeView> {
  @override
  final Iterable<Type> types = const [
    AppearanceCostumeView,
    _$AppearanceCostumeView
  ];

  @override
  final String wireName = r'AppearanceCostumeView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AppearanceCostumeView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    AppearanceCostumeView object, {
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
    required AppearanceCostumeViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  AppearanceCostumeView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AppearanceCostumeViewBuilder();
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
