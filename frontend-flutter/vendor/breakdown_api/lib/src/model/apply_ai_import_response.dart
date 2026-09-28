// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/unapplied_costume.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_ai_import_response.g.dart';

/// ApplyAiImportResponse
///
/// Properties:
/// * [appliedCount]
/// * [createdCharacters] - Figures the script apply created. A figure named by several draft rows is created once, so this is not `applied_count`-related. `0` for a schedule apply, which has no figures.
/// * [createdCostumes] - Costumes the script apply created (unassigned, then bound).
/// * [createdDays]
/// * [plannedSceneShoots]
/// * [unappliedCostumes] - Costume rows that did **not** become a `Costume`, each with the reason. An apply that created a costume but could not bind it reports the row here while `created_costumes` still counts it — a partially applied row must never look like a fully applied one.
@BuiltValue()
abstract class ApplyAiImportResponse
    implements Built<ApplyAiImportResponse, ApplyAiImportResponseBuilder> {
  @BuiltValueField(wireName: r'applied_count')
  int get appliedCount;

  /// Figures the script apply created. A figure named by several draft rows is created once, so this is not `applied_count`-related. `0` for a schedule apply, which has no figures.
  @BuiltValueField(wireName: r'created_characters')
  int get createdCharacters;

  /// Costumes the script apply created (unassigned, then bound).
  @BuiltValueField(wireName: r'created_costumes')
  int get createdCostumes;

  @BuiltValueField(wireName: r'created_days')
  int get createdDays;

  @BuiltValueField(wireName: r'planned_scene_shoots')
  int get plannedSceneShoots;

  /// Costume rows that did **not** become a `Costume`, each with the reason. An apply that created a costume but could not bind it reports the row here while `created_costumes` still counts it — a partially applied row must never look like a fully applied one.
  @BuiltValueField(wireName: r'unapplied_costumes')
  BuiltList<UnappliedCostume> get unappliedCostumes;

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
    yield r'created_characters';
    yield serializers.serialize(
      object.createdCharacters,
      specifiedType: const FullType(int),
    );
    yield r'created_costumes';
    yield serializers.serialize(
      object.createdCostumes,
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
    yield r'unapplied_costumes';
    yield serializers.serialize(
      object.unappliedCostumes,
      specifiedType: const FullType(BuiltList, [FullType(UnappliedCostume)]),
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
        case r'created_characters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdCharacters = valueDes;
          break;
        case r'created_costumes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.createdCostumes = valueDes;
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
        case r'unapplied_costumes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(UnappliedCostume)]),
          ) as BuiltList<UnappliedCostume>;
          result.unappliedCostumes.replace(valueDes);
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
