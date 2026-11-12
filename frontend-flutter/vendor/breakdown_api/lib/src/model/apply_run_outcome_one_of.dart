// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/apply_import_summary.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_run_outcome_one_of.g.dart';

/// The run completed and applied its plan (fully or partially — the summary reports the difference through `unapplied_outfits`).
///
/// Properties:
/// * [succeeded] - The run completed and applied its plan (fully or partially — the summary reports the difference through `unapplied_outfits`).
@BuiltValue()
abstract class ApplyRunOutcomeOneOf
    implements Built<ApplyRunOutcomeOneOf, ApplyRunOutcomeOneOfBuilder> {
  /// The run completed and applied its plan (fully or partially — the summary reports the difference through `unapplied_outfits`).
  @BuiltValueField(wireName: r'succeeded')
  ApplyImportSummary get succeeded;

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
    yield r'succeeded';
    yield serializers.serialize(
      object.succeeded,
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
        case r'succeeded':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApplyImportSummary),
          ) as ApplyImportSummary;
          result.succeeded.replace(valueDes);
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
