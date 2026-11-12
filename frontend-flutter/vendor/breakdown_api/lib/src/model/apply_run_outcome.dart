// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_run_outcome_one_of.dart';
import 'package:breakdown_api/src/model/apply_run_outcome_one_of1.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/apply_import_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'apply_run_outcome.g.dart';

/// What a finished apply run left on the job's run slot (issue #899, design D4).  Persisted as `apply_result` JSONB by the worker, so the outcome outlives the request that asked for it: a client that re-attaches after the run finished reads it off `GET /ai-import/jobs/{id}` or off the apply stream's terminal frame — no second `POST` needed.  A failed run carries the **registered problem `code`** (ADR-031), never a `detail`-only string, so the client's error narrative is code-driven exactly like every other apply failure. The human-readable detail stays in the log.
///
/// Properties:
/// * [outcome]
/// * [summary]
/// * [code] - Stable problem code (e.g. `ai-import.apply-missing-shooting-day-group`).
@BuiltValue()
abstract class ApplyRunOutcome
    implements Built<ApplyRunOutcome, ApplyRunOutcomeBuilder> {
  /// One Of [ApplyRunOutcomeOneOf], [ApplyRunOutcomeOneOf1]
  OneOf get oneOf;

  ApplyRunOutcome._();

  factory ApplyRunOutcome([void updates(ApplyRunOutcomeBuilder b)]) =
      _$ApplyRunOutcome;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyRunOutcomeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyRunOutcome> get serializer =>
      _$ApplyRunOutcomeSerializer();
}

class _$ApplyRunOutcomeSerializer
    implements PrimitiveSerializer<ApplyRunOutcome> {
  @override
  final Iterable<Type> types = const [ApplyRunOutcome, _$ApplyRunOutcome];

  @override
  final String wireName = r'ApplyRunOutcome';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyRunOutcome object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {}

  @override
  Object serialize(
    Serializers serializers,
    ApplyRunOutcome object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value,
        specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  ApplyRunOutcome deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyRunOutcomeBuilder();
    Object? oneOfDataSrc;
    final targetType = const FullType(OneOf, [
      FullType(ApplyRunOutcomeOneOf),
      FullType(ApplyRunOutcomeOneOf1),
    ]);
    oneOfDataSrc = serialized;
    result.oneOf = serializers.deserialize(oneOfDataSrc,
        specifiedType: targetType) as OneOf;
    return result.build();
  }
}

class ApplyRunOutcomeOutcomeEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'failed')
  static const ApplyRunOutcomeOutcomeEnum failed =
      _$applyRunOutcomeOutcomeEnum_failed;

  static Serializer<ApplyRunOutcomeOutcomeEnum> get serializer =>
      _$applyRunOutcomeOutcomeEnumSerializer;

  const ApplyRunOutcomeOutcomeEnum._(String name) : super(name);

  static BuiltSet<ApplyRunOutcomeOutcomeEnum> get values =>
      _$applyRunOutcomeOutcomeEnumValues;
  static ApplyRunOutcomeOutcomeEnum valueOf(String name) =>
      _$applyRunOutcomeOutcomeEnumValueOf(name);
}
