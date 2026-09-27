// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'costume_decision.g.dart';

/// Reviewer decision for one costume row of a draft row. A costume is accepted or rejected *independently of its scene* (spec `ai-import`: the preview exposes each costume row for its own decision).
///
/// Properties:
/// * [accepted] - `false` rejects the costume: no `Costume` is created and the scene row is unaffected.
/// * [ordinal] - Index into the draft row's `costumes` list.
@BuiltValue()
abstract class CostumeDecision
    implements Built<CostumeDecision, CostumeDecisionBuilder> {
  /// `false` rejects the costume: no `Costume` is created and the scene row is unaffected.
  @BuiltValueField(wireName: r'accepted')
  bool get accepted;

  /// Index into the draft row's `costumes` list.
  @BuiltValueField(wireName: r'ordinal')
  int get ordinal;

  CostumeDecision._();

  factory CostumeDecision([void updates(CostumeDecisionBuilder b)]) =
      _$CostumeDecision;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostumeDecisionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostumeDecision> get serializer =>
      _$CostumeDecisionSerializer();
}

class _$CostumeDecisionSerializer
    implements PrimitiveSerializer<CostumeDecision> {
  @override
  final Iterable<Type> types = const [CostumeDecision, _$CostumeDecision];

  @override
  final String wireName = r'CostumeDecision';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostumeDecision object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'accepted';
    yield serializers.serialize(
      object.accepted,
      specifiedType: const FullType(bool),
    );
    yield r'ordinal';
    yield serializers.serialize(
      object.ordinal,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CostumeDecision object, {
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
    required CostumeDecisionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accepted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.accepted = valueDes;
          break;
        case r'ordinal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.ordinal = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CostumeDecision deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostumeDecisionBuilder();
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
