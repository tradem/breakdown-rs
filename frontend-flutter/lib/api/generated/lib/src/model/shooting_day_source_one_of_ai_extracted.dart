// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'shooting_day_source_one_of_ai_extracted.g.dart';

/// ShootingDaySourceOneOfAiExtracted
///
/// Properties:
/// * [confidence]
/// * [documentId]
/// * [externalRef]
@BuiltValue()
abstract class ShootingDaySourceOneOfAiExtracted
    implements
        Built<ShootingDaySourceOneOfAiExtracted,
            ShootingDaySourceOneOfAiExtractedBuilder> {
  @BuiltValueField(wireName: r'confidence')
  double get confidence;

  @BuiltValueField(wireName: r'document_id')
  String get documentId;

  @BuiltValueField(wireName: r'external_ref')
  String? get externalRef;

  ShootingDaySourceOneOfAiExtracted._();

  factory ShootingDaySourceOneOfAiExtracted(
          [void updates(ShootingDaySourceOneOfAiExtractedBuilder b)]) =
      _$ShootingDaySourceOneOfAiExtracted;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShootingDaySourceOneOfAiExtractedBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShootingDaySourceOneOfAiExtracted> get serializer =>
      _$ShootingDaySourceOneOfAiExtractedSerializer();
}

class _$ShootingDaySourceOneOfAiExtractedSerializer
    implements PrimitiveSerializer<ShootingDaySourceOneOfAiExtracted> {
  @override
  final Iterable<Type> types = const [
    ShootingDaySourceOneOfAiExtracted,
    _$ShootingDaySourceOneOfAiExtracted
  ];

  @override
  final String wireName = r'ShootingDaySourceOneOfAiExtracted';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShootingDaySourceOneOfAiExtracted object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'confidence';
    yield serializers.serialize(
      object.confidence,
      specifiedType: const FullType(double),
    );
    yield r'document_id';
    yield serializers.serialize(
      object.documentId,
      specifiedType: const FullType(String),
    );
    if (object.externalRef != null) {
      yield r'external_ref';
      yield serializers.serialize(
        object.externalRef,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ShootingDaySourceOneOfAiExtracted object, {
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
    required ShootingDaySourceOneOfAiExtractedBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'confidence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.confidence = valueDes;
          break;
        case r'document_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.documentId = valueDes;
          break;
        case r'external_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.externalRef = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ShootingDaySourceOneOfAiExtracted deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShootingDaySourceOneOfAiExtractedBuilder();
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
