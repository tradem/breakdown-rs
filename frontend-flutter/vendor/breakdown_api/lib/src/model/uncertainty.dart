// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/uncertainty_kind.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'uncertainty.g.dart';

/// Uncertainty
///
/// Properties:
/// * [field]
/// * [kind] - `serde(default)` so a preview stored before this field existed keeps blocking exactly as it did: an absent kind is a `FieldAmbiguity`.
/// * [note]
/// * [sceneIndex]
/// * [suggestedValue]
@BuiltValue()
abstract class Uncertainty implements Built<Uncertainty, UncertaintyBuilder> {
  @BuiltValueField(wireName: r'field')
  String get field;

  /// `serde(default)` so a preview stored before this field existed keeps blocking exactly as it did: an absent kind is a `FieldAmbiguity`.
  @BuiltValueField(wireName: r'kind')
  UncertaintyKind? get kind;
  // enum kindEnum {  field_ambiguity,  dropped_row,  };

  @BuiltValueField(wireName: r'note')
  String get note;

  @BuiltValueField(wireName: r'scene_index')
  int get sceneIndex;

  @BuiltValueField(wireName: r'suggested_value')
  String? get suggestedValue;

  Uncertainty._();

  factory Uncertainty([void updates(UncertaintyBuilder b)]) = _$Uncertainty;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UncertaintyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Uncertainty> get serializer => _$UncertaintySerializer();
}

class _$UncertaintySerializer implements PrimitiveSerializer<Uncertainty> {
  @override
  final Iterable<Type> types = const [Uncertainty, _$Uncertainty];

  @override
  final String wireName = r'Uncertainty';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Uncertainty object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'field';
    yield serializers.serialize(
      object.field,
      specifiedType: const FullType(String),
    );
    if (object.kind != null) {
      yield r'kind';
      yield serializers.serialize(
        object.kind,
        specifiedType: const FullType(UncertaintyKind),
      );
    }
    yield r'note';
    yield serializers.serialize(
      object.note,
      specifiedType: const FullType(String),
    );
    yield r'scene_index';
    yield serializers.serialize(
      object.sceneIndex,
      specifiedType: const FullType(int),
    );
    if (object.suggestedValue != null) {
      yield r'suggested_value';
      yield serializers.serialize(
        object.suggestedValue,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    Uncertainty object, {
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
    required UncertaintyBuilder result,
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
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(UncertaintyKind),
          ) as UncertaintyKind?;
          if (valueDes == null) continue;
          result.kind = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.note = valueDes;
          break;
        case r'scene_index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sceneIndex = valueDes;
          break;
        case r'suggested_value':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.suggestedValue = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Uncertainty deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UncertaintyBuilder();
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
