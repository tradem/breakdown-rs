// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/draft_scene.dart';
import 'package:breakdown_api/src/model/uncertainty.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'script_context.g.dart';

/// Static LLM target for script extraction. Optional fields express the null-on-doubt rule: uncertain values must not be asserted by the model.
///
/// Properties:
/// * [scenes]
/// * [title]
/// * [uncertainties]
@BuiltValue()
abstract class ScriptContext
    implements Built<ScriptContext, ScriptContextBuilder> {
  @BuiltValueField(wireName: r'scenes')
  BuiltList<DraftScene> get scenes;

  @BuiltValueField(wireName: r'title')
  String? get title;

  @BuiltValueField(wireName: r'uncertainties')
  BuiltList<Uncertainty> get uncertainties;

  ScriptContext._();

  factory ScriptContext([void updates(ScriptContextBuilder b)]) =
      _$ScriptContext;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScriptContextBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScriptContext> get serializer =>
      _$ScriptContextSerializer();
}

class _$ScriptContextSerializer implements PrimitiveSerializer<ScriptContext> {
  @override
  final Iterable<Type> types = const [ScriptContext, _$ScriptContext];

  @override
  final String wireName = r'ScriptContext';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScriptContext object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'scenes';
    yield serializers.serialize(
      object.scenes,
      specifiedType: const FullType(BuiltList, [FullType(DraftScene)]),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'uncertainties';
    yield serializers.serialize(
      object.uncertainties,
      specifiedType: const FullType(BuiltList, [FullType(Uncertainty)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ScriptContext object, {
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
    required ScriptContextBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'scenes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DraftScene)]),
          ) as BuiltList<DraftScene>;
          result.scenes.replace(valueDes);
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.title = valueDes;
          break;
        case r'uncertainties':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Uncertainty)]),
          ) as BuiltList<Uncertainty>;
          result.uncertainties.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScriptContext deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScriptContextBuilder();
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
