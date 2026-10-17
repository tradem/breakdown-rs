// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'image_cost_breakdown.g.dart';

/// Image-generation cost of one import (#673 extensibility slot). Always `None` for script/schedule text imports.
///
/// Properties:
/// * [imageNanoPerUnit] - Snapshot of the flat per-image rate, when that billing kind applies.
/// * [imageOutputRateNanoPerMillion] - Snapshot of the per-million-token rate, when that billing kind applies.
/// * [imageOutputTokens] - Image-output tokens consumed (the per-token billing path).
/// * [images] - Number of generated images.
/// * [totalNano]
@BuiltValue()
abstract class ImageCostBreakdown
    implements Built<ImageCostBreakdown, ImageCostBreakdownBuilder> {
  /// Snapshot of the flat per-image rate, when that billing kind applies.
  @BuiltValueField(wireName: r'image_nano_per_unit')
  int? get imageNanoPerUnit;

  /// Snapshot of the per-million-token rate, when that billing kind applies.
  @BuiltValueField(wireName: r'image_output_rate_nano_per_million')
  int? get imageOutputRateNanoPerMillion;

  /// Image-output tokens consumed (the per-token billing path).
  @BuiltValueField(wireName: r'image_output_tokens')
  int get imageOutputTokens;

  /// Number of generated images.
  @BuiltValueField(wireName: r'images')
  int get images;

  @BuiltValueField(wireName: r'total_nano')
  int get totalNano;

  ImageCostBreakdown._();

  factory ImageCostBreakdown([void updates(ImageCostBreakdownBuilder b)]) =
      _$ImageCostBreakdown;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ImageCostBreakdownBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ImageCostBreakdown> get serializer =>
      _$ImageCostBreakdownSerializer();
}

class _$ImageCostBreakdownSerializer
    implements PrimitiveSerializer<ImageCostBreakdown> {
  @override
  final Iterable<Type> types = const [ImageCostBreakdown, _$ImageCostBreakdown];

  @override
  final String wireName = r'ImageCostBreakdown';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ImageCostBreakdown object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.imageNanoPerUnit != null) {
      yield r'image_nano_per_unit';
      yield serializers.serialize(
        object.imageNanoPerUnit,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.imageOutputRateNanoPerMillion != null) {
      yield r'image_output_rate_nano_per_million';
      yield serializers.serialize(
        object.imageOutputRateNanoPerMillion,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'image_output_tokens';
    yield serializers.serialize(
      object.imageOutputTokens,
      specifiedType: const FullType(int),
    );
    yield r'images';
    yield serializers.serialize(
      object.images,
      specifiedType: const FullType(int),
    );
    yield r'total_nano';
    yield serializers.serialize(
      object.totalNano,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ImageCostBreakdown object, {
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
    required ImageCostBreakdownBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'image_nano_per_unit':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.imageNanoPerUnit = valueDes;
          break;
        case r'image_output_rate_nano_per_million':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.imageOutputRateNanoPerMillion = valueDes;
          break;
        case r'image_output_tokens':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.imageOutputTokens = valueDes;
          break;
        case r'images':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.images = valueDes;
          break;
        case r'total_nano':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalNano = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ImageCostBreakdown deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ImageCostBreakdownBuilder();
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
