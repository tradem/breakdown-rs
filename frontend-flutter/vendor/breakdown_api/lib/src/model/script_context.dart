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

/// Static LLM target for script extraction. Optional fields express the null-on-doubt rule: uncertain values must not be asserted by the model.  The three `scenes_*` counters are **server-derived reconciliation data** (issue #758), not model output: the extraction worker overwrites them at the storing boundary from what the deterministic scan and the model actually produced. They exist because the pipeline had no way to notice that a 57-heading script had turned into a 4-row preview — every consumer saw only `scenes.len()`. All three are additive with `serde(default)`, so previews stored before this field existed still load (they simply carry `0`, which a client renders as \"not recorded\").
///
/// Properties:
/// * [scenes]
/// * [scenesDetected] - Scene headings the deterministic scan detected — the chunk count after [`merge_duplicate_scene_numbers`] (issue #758). This is the number the document states, not the number the model produced.
/// * [scenesExtracted] - Preview rows the model itself returned, summed over all chunks (issue #758). Deliberately **excludes** rows rebuilt from document metadata, so `scenes_extracted < scenes_detected` is the visible shortfall.
/// * [scenesSynthesized] - Preview rows rebuilt from the deterministic heading because their chunk returned no rows at all (issue #758). `scenes.len()` is `scenes_extracted + scenes_synthesized`; a nonzero value is the code-keyed degradation signal, mirrored per row by a `DroppedRow` uncertainty with `field = \"extraction\"`.
/// * [title]
/// * [uncertainties]
@BuiltValue()
abstract class ScriptContext
    implements Built<ScriptContext, ScriptContextBuilder> {
  @BuiltValueField(wireName: r'scenes')
  BuiltList<DraftScene> get scenes;

  /// Scene headings the deterministic scan detected — the chunk count after [`merge_duplicate_scene_numbers`] (issue #758). This is the number the document states, not the number the model produced.
  @BuiltValueField(wireName: r'scenes_detected')
  int? get scenesDetected;

  /// Preview rows the model itself returned, summed over all chunks (issue #758). Deliberately **excludes** rows rebuilt from document metadata, so `scenes_extracted < scenes_detected` is the visible shortfall.
  @BuiltValueField(wireName: r'scenes_extracted')
  int? get scenesExtracted;

  /// Preview rows rebuilt from the deterministic heading because their chunk returned no rows at all (issue #758). `scenes.len()` is `scenes_extracted + scenes_synthesized`; a nonzero value is the code-keyed degradation signal, mirrored per row by a `DroppedRow` uncertainty with `field = \"extraction\"`.
  @BuiltValueField(wireName: r'scenes_synthesized')
  int? get scenesSynthesized;

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
    if (object.scenesDetected != null) {
      yield r'scenes_detected';
      yield serializers.serialize(
        object.scenesDetected,
        specifiedType: const FullType(int),
      );
    }
    if (object.scenesExtracted != null) {
      yield r'scenes_extracted';
      yield serializers.serialize(
        object.scenesExtracted,
        specifiedType: const FullType(int),
      );
    }
    if (object.scenesSynthesized != null) {
      yield r'scenes_synthesized';
      yield serializers.serialize(
        object.scenesSynthesized,
        specifiedType: const FullType(int),
      );
    }
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
        case r'scenes_detected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.scenesDetected = valueDes;
          break;
        case r'scenes_extracted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.scenesExtracted = valueDes;
          break;
        case r'scenes_synthesized':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.scenesSynthesized = valueDes;
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
