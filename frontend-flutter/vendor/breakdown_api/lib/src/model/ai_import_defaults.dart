// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_defaults.g.dart';

/// Wire shape for `GET /v1/ai-import/defaults` (issue #471): the deployment's single-source prompt defaults (script/schedule) read from `AI_IMPORT_DEFAULT_PROMPTS_PATH` or the built-in fallback TOML — the same prompts the import workers seed from.
///
/// Properties:
/// * [schedule] - Default prompt seed for schedule imports.
/// * [script] - Default prompt seed for script imports.
@BuiltValue()
abstract class AiImportDefaults
    implements Built<AiImportDefaults, AiImportDefaultsBuilder> {
  /// Default prompt seed for schedule imports.
  @BuiltValueField(wireName: r'schedule')
  String get schedule;

  /// Default prompt seed for script imports.
  @BuiltValueField(wireName: r'script')
  String get script;

  AiImportDefaults._();

  factory AiImportDefaults([void updates(AiImportDefaultsBuilder b)]) =
      _$AiImportDefaults;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiImportDefaultsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiImportDefaults> get serializer =>
      _$AiImportDefaultsSerializer();
}

class _$AiImportDefaultsSerializer
    implements PrimitiveSerializer<AiImportDefaults> {
  @override
  final Iterable<Type> types = const [AiImportDefaults, _$AiImportDefaults];

  @override
  final String wireName = r'AiImportDefaults';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiImportDefaults object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'schedule';
    yield serializers.serialize(
      object.schedule,
      specifiedType: const FullType(String),
    );
    yield r'script';
    yield serializers.serialize(
      object.script,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiImportDefaults object, {
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
    required AiImportDefaultsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'schedule':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.schedule = valueDes;
          break;
        case r'script':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.script = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiImportDefaults deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiImportDefaultsBuilder();
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
