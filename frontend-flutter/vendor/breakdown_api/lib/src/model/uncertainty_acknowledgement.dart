// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'uncertainty_acknowledgement.g.dart';

/// The reviewer's acknowledgement of ONE blocking uncertainty (issue #663).  Request-carried by design: a stored preview is an immutable payload blob (content-addressed handle, no update path), so the resolution lives in the apply request next to the other reviewer decisions (`mappings`, `episode_groups`) instead of mutating the preview. Acknowledge semantics: the reviewer confirms the ambiguous (or absent) value is acceptable and the row applies as extracted — `Uncertainty.suggested_value` is display-only; correcting a *wrong* value happens post-apply via normal scene editing. Identifying pair is `(scene_index, field)` — exactly the fields the extraction prompt reports an uncertainty with.
///
/// Properties:
/// * [field] - The field the uncertainty names (`Uncertainty.field`).
/// * [sceneIndex] - The scene the uncertainty is attached to (`Uncertainty.scene_index`).
@BuiltValue()
abstract class UncertaintyAcknowledgement
    implements
        Built<UncertaintyAcknowledgement, UncertaintyAcknowledgementBuilder> {
  /// The field the uncertainty names (`Uncertainty.field`).
  @BuiltValueField(wireName: r'field')
  String get field;

  /// The scene the uncertainty is attached to (`Uncertainty.scene_index`).
  @BuiltValueField(wireName: r'scene_index')
  int get sceneIndex;

  UncertaintyAcknowledgement._();

  factory UncertaintyAcknowledgement(
          [void updates(UncertaintyAcknowledgementBuilder b)]) =
      _$UncertaintyAcknowledgement;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UncertaintyAcknowledgementBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UncertaintyAcknowledgement> get serializer =>
      _$UncertaintyAcknowledgementSerializer();
}

class _$UncertaintyAcknowledgementSerializer
    implements PrimitiveSerializer<UncertaintyAcknowledgement> {
  @override
  final Iterable<Type> types = const [
    UncertaintyAcknowledgement,
    _$UncertaintyAcknowledgement
  ];

  @override
  final String wireName = r'UncertaintyAcknowledgement';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UncertaintyAcknowledgement object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'field';
    yield serializers.serialize(
      object.field,
      specifiedType: const FullType(String),
    );
    yield r'scene_index';
    yield serializers.serialize(
      object.sceneIndex,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UncertaintyAcknowledgement object, {
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
    required UncertaintyAcknowledgementBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'field':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.field = valueDes;
          break;
        case r'scene_index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sceneIndex = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UncertaintyAcknowledgement deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UncertaintyAcknowledgementBuilder();
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
