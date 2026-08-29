// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/photo_variant_view.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/photo_binding.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_view.g.dart';

/// Complete photo read model, populated by the projector.
///
/// Properties:
/// * [binding] - What this photo is attached to (Costume or Continuity).
/// * [contentType]
/// * [exifStrippedAt]
/// * [id] - Opaque identifier for a `Photo` aggregate.  A `Photo` is an event-sourced aggregate that tracks the lifecycle (upload, normalisation, variant generation, deletion) of a costume photo. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`. The actual bytes are stored in Garage via the `PhotoStorage` port.
/// * [sizeBytes]
/// * [variants]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class PhotoView implements Built<PhotoView, PhotoViewBuilder> {
  /// What this photo is attached to (Costume or Continuity).
  @BuiltValueField(wireName: r'binding')
  PhotoBinding get binding;

  @BuiltValueField(wireName: r'content_type')
  String get contentType;

  @BuiltValueField(wireName: r'exif_stripped_at')
  DateTime? get exifStrippedAt;

  /// Opaque identifier for a `Photo` aggregate.  A `Photo` is an event-sourced aggregate that tracks the lifecycle (upload, normalisation, variant generation, deletion) of a costume photo. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`. The actual bytes are stored in Garage via the `PhotoStorage` port.
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'size_bytes')
  int get sizeBytes;

  @BuiltValueField(wireName: r'variants')
  BuiltList<PhotoVariantView> get variants;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  PhotoView._();

  factory PhotoView([void updates(PhotoViewBuilder b)]) = _$PhotoView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoView> get serializer => _$PhotoViewSerializer();
}

class _$PhotoViewSerializer implements PrimitiveSerializer<PhotoView> {
  @override
  final Iterable<Type> types = const [PhotoView, _$PhotoView];

  @override
  final String wireName = r'PhotoView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'binding';
    yield serializers.serialize(
      object.binding,
      specifiedType: const FullType(PhotoBinding),
    );
    yield r'content_type';
    yield serializers.serialize(
      object.contentType,
      specifiedType: const FullType(String),
    );
    if (object.exifStrippedAt != null) {
      yield r'exif_stripped_at';
      yield serializers.serialize(
        object.exifStrippedAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
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
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoView object, {
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
    required PhotoViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'binding':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PhotoBinding),
          ) as PhotoBinding;
          result.binding.replace(valueDes);
          break;
        case r'content_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.contentType = valueDes;
          break;
        case r'exif_stripped_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.exifStrippedAt = valueDes;
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
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoViewBuilder();
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
