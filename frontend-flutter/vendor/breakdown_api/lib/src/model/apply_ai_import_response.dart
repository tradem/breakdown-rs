// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_ai_import_response.g.dart';

/// ApplyAiImportResponse
///
/// Properties:
/// * [appliedCount]
/// * [createdDays]
/// * [plannedSceneShoots]
@BuiltValue()
abstract class ApplyAiImportResponse
    implements Built<ApplyAiImportResponse, ApplyAiImportResponseBuilder> {
  @BuiltValueField(wireName: r'applied_count')
  int get appliedCount;

  @BuiltValueField(wireName: r'created_days')
  int get createdDays;

  @BuiltValueField(wireName: r'planned_scene_shoots')
  int get plannedSceneShoots;

  ApplyAiImportResponse._();

  factory ApplyAiImportResponse(
      [void updates(ApplyAiImportResponseBuilder b)]) = _$ApplyAiImportResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyAiImportResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyAiImportResponse> get serializer =>
      _$ApplyAiImportResponseSerializer();
}

class _$ApplyAiImportResponseSerializer
    implements PrimitiveSerializer<ApplyAiImportResponse> {
  @override
  final Iterable<Type> types = const [
    ApplyAiImportResponse,
    _$ApplyAiImportResponse
  ];

  @override
  final String wireName = r'ApplyAiImportResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyAiImportResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied_count';
    yield serializers.serialize(
      object.appliedCount,
      specifiedType: const FullType(int),
    );
    yield r'created_days';
    yield serializers.serialize(
      object.createdDays,
      specifiedType: const FullType(int),
    );
    yield r'planned_scene_shoots';
    yield serializers.serialize(
      object.plannedSceneShoots,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyAiImportResponse object, {
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
    required ApplyAiImportResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.appliedCount = valueDes;
          break;
        case r'created_days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdDays = valueDes;
          break;
        case r'planned_scene_shoots':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.plannedSceneShoots = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyAiImportResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyAiImportResponseBuilder();
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
