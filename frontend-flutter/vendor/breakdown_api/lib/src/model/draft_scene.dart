// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_scene.g.dart';

/// DraftScene
///
/// Properties:
/// * [characters]
/// * [draftRef]
/// * [location]
/// * [mood]
/// * [sceneNumber]
/// * [scriptDay]
/// * [summary]
@BuiltValue()
abstract class DraftScene implements Built<DraftScene, DraftSceneBuilder> {
  @BuiltValueField(wireName: r'characters')
  BuiltList<String> get characters;

  @BuiltValueField(wireName: r'draft_ref')
  String get draftRef;

  @BuiltValueField(wireName: r'location')
  String? get location;

  @BuiltValueField(wireName: r'mood')
  String? get mood;

  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  @BuiltValueField(wireName: r'script_day')
  String? get scriptDay;

  @BuiltValueField(wireName: r'summary')
  String? get summary;

  DraftScene._();

  factory DraftScene([void updates(DraftSceneBuilder b)]) = _$DraftScene;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftSceneBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftScene> get serializer => _$DraftSceneSerializer();
}

class _$DraftSceneSerializer implements PrimitiveSerializer<DraftScene> {
  @override
  final Iterable<Type> types = const [DraftScene, _$DraftScene];

  @override
  final String wireName = r'DraftScene';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftScene object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'characters';
    yield serializers.serialize(
      object.characters,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'draft_ref';
    yield serializers.serialize(
      object.draftRef,
      specifiedType: const FullType(String),
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
    if (object.summary != null) {
      yield r'summary';
      yield serializers.serialize(
        object.summary,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftScene object, {
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
    required DraftSceneBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'characters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.characters.replace(valueDes);
          break;
        case r'draft_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.draftRef = valueDes;
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
        case r'summary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.summary = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftScene deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftSceneBuilder();
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
