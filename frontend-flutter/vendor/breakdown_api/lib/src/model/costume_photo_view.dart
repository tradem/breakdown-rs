// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/photo_variant_view.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'costume_photo_view.g.dart';

/// Linked photo reference for a costume, enriched with variant metadata.
///
/// Properties:
/// * [contentType] - MIME type of the uploaded original (e.g. `image/jpeg`).
/// * [id]
/// * [sizeBytes] - Size of the re-encoded original in bytes.
/// * [variants] - Generation status and size of each variant.
@BuiltValue()
abstract class CostumePhotoView
    implements Built<CostumePhotoView, CostumePhotoViewBuilder> {
  /// MIME type of the uploaded original (e.g. `image/jpeg`).
  @BuiltValueField(wireName: r'content_type')
  String get contentType;

  @BuiltValueField(wireName: r'id')
  String get id;

  /// Size of the re-encoded original in bytes.
  @BuiltValueField(wireName: r'size_bytes')
  int get sizeBytes;

  /// Generation status and size of each variant.
  @BuiltValueField(wireName: r'variants')
  BuiltList<PhotoVariantView> get variants;

  CostumePhotoView._();

  factory CostumePhotoView([void updates(CostumePhotoViewBuilder b)]) =
      _$CostumePhotoView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostumePhotoViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostumePhotoView> get serializer =>
      _$CostumePhotoViewSerializer();
}

class _$CostumePhotoViewSerializer
    implements PrimitiveSerializer<CostumePhotoView> {
  @override
  final Iterable<Type> types = const [CostumePhotoView, _$CostumePhotoView];

  @override
  final String wireName = r'CostumePhotoView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostumePhotoView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'content_type';
    yield serializers.serialize(
      object.contentType,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'size_bytes';
    yield serializers.serialize(
      object.sizeBytes,
      specifiedType: const FullType(int),
    );
    yield r'variants';
    yield serializers.serialize(
      object.variants,
      specifiedType: const FullType(BuiltList, [FullType(PhotoVariantView)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CostumePhotoView object, {
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
    required CostumePhotoViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'content_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.contentType = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'size_bytes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sizeBytes = valueDes;
          break;
        case r'variants':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(PhotoVariantView)]),
          ) as BuiltList<PhotoVariantView>;
          result.variants.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CostumePhotoView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostumePhotoViewBuilder();
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
