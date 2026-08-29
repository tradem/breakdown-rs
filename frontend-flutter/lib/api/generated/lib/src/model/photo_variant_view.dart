// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/variant_status.dart';
import 'package:breakdown_api/src/model/photo_variant.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_variant_view.g.dart';

/// A single variant's public view.
///
/// Properties:
/// * [kind]
/// * [sizeBytes]
/// * [status]
@BuiltValue()
abstract class PhotoVariantView
    implements Built<PhotoVariantView, PhotoVariantViewBuilder> {
  @BuiltValueField(wireName: r'kind')
  PhotoVariant get kind;
  // enum kindEnum {  Original,  Thumb,  Medium,  };

  @BuiltValueField(wireName: r'size_bytes')
  int get sizeBytes;

  @BuiltValueField(wireName: r'status')
  VariantStatus get status;
  // enum statusEnum {  Pending,  Ready,  Failed,  };

  PhotoVariantView._();

  factory PhotoVariantView([void updates(PhotoVariantViewBuilder b)]) =
      _$PhotoVariantView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoVariantViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoVariantView> get serializer =>
      _$PhotoVariantViewSerializer();
}

class _$PhotoVariantViewSerializer
    implements PrimitiveSerializer<PhotoVariantView> {
  @override
  final Iterable<Type> types = const [PhotoVariantView, _$PhotoVariantView];

  @override
  final String wireName = r'PhotoVariantView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoVariantView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(PhotoVariant),
    );
    yield r'size_bytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(VariantStatus),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoVariantView object, {
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
    required PhotoVariantViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PhotoVariant),
          ) as PhotoVariant;
          result.kind = valueDes;
          break;
        case r'size_bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(VariantStatus),
          ) as VariantStatus;
          result.status = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoVariantView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoVariantViewBuilder();
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
