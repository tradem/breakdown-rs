// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/apply_import_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_run_outcome_one_of.g.dart';

/// The run completed and applied its plan (fully or partially — the summary reports the difference through `unapplied_outfits`).
///
/// Properties:
/// * [outcome]
/// * [summary]
@BuiltValue()
abstract class ApplyRunOutcomeOneOf
    implements Built<ApplyRunOutcomeOneOf, ApplyRunOutcomeOneOfBuilder> {
  @BuiltValueField(wireName: r'outcome')
  ApplyRunOutcomeOneOfOutcomeEnum get outcome;
  // enum outcomeEnum {  succeeded,  };

  @BuiltValueField(wireName: r'summary')
  ApplyImportSummary get summary;

  ApplyRunOutcomeOneOf._();

  factory ApplyRunOutcomeOneOf([void updates(ApplyRunOutcomeOneOfBuilder b)]) =
      _$ApplyRunOutcomeOneOf;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyRunOutcomeOneOfBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyRunOutcomeOneOf> get serializer =>
      _$ApplyRunOutcomeOneOfSerializer();
}

class _$ApplyRunOutcomeOneOfSerializer
    implements PrimitiveSerializer<ApplyRunOutcomeOneOf> {
  @override
  final Iterable<Type> types = const [
    ApplyRunOutcomeOneOf,
    _$ApplyRunOutcomeOneOf
  ];

  @override
  final String wireName = r'ApplyRunOutcomeOneOf';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyRunOutcomeOneOf object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'outcome';
    yield serializers.serialize(
      object.outcome,
      specifiedType: const FullType(ApplyRunOutcomeOneOfOutcomeEnum),
    );
    yield r'summary';
    yield serializers.serialize(
      object.summary,
      specifiedType: const FullType(ApplyImportSummary),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyRunOutcomeOneOf object, {
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
    required ApplyRunOutcomeOneOfBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'outcome':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyRunOutcomeOneOfOutcomeEnum),
          ) as ApplyRunOutcomeOneOfOutcomeEnum;
          result.outcome = valueDes;
          break;
        case r'summary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyImportSummary),
          ) as ApplyImportSummary;
          result.summary.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyRunOutcomeOneOf deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyRunOutcomeOneOfBuilder();
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

class ApplyRunOutcomeOneOfOutcomeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'succeeded')
  static const ApplyRunOutcomeOneOfOutcomeEnum succeeded =
      _$applyRunOutcomeOneOfOutcomeEnum_succeeded;

  static Serializer<ApplyRunOutcomeOneOfOutcomeEnum> get serializer =>
      _$applyRunOutcomeOneOfOutcomeEnumSerializer;

  const ApplyRunOutcomeOneOfOutcomeEnum._(String name) : super(name);

  static BuiltSet<ApplyRunOutcomeOneOfOutcomeEnum> get values =>
      _$applyRunOutcomeOneOfOutcomeEnumValues;
  static ApplyRunOutcomeOneOfOutcomeEnum valueOf(String name) =>
      _$applyRunOutcomeOneOfOutcomeEnumValueOf(name);
}
