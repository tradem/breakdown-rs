// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'link_continuity_photo_request.g.dart';

/// LinkContinuityPhotoRequest
///
/// Properties:
/// * [photoId] - Opaque identifier for a `Photo` aggregate.  A `Photo` is an event-sourced aggregate that tracks the lifecycle (upload, normalisation, variant generation, deletion) of a costume photo. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`. The actual bytes are stored in Garage via the `PhotoStorage` port.
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class LinkContinuityPhotoRequest
    implements
        Built<LinkContinuityPhotoRequest, LinkContinuityPhotoRequestBuilder> {
  /// Opaque identifier for a `Photo` aggregate.  A `Photo` is an event-sourced aggregate that tracks the lifecycle (upload, normalisation, variant generation, deletion) of a costume photo. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`. The actual bytes are stored in Garage via the `PhotoStorage` port.
  @BuiltValueField(wireName: r'photo_id')
  String get photoId;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  LinkContinuityPhotoRequest._();

  factory LinkContinuityPhotoRequest(
          [void updates(LinkContinuityPhotoRequestBuilder b)]) =
      _$LinkContinuityPhotoRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LinkContinuityPhotoRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LinkContinuityPhotoRequest> get serializer =>
      _$LinkContinuityPhotoRequestSerializer();
}

class _$LinkContinuityPhotoRequestSerializer
    implements PrimitiveSerializer<LinkContinuityPhotoRequest> {
  @override
  final Iterable<Type> types = const [
    LinkContinuityPhotoRequest,
    _$LinkContinuityPhotoRequest
  ];

  @override
  final String wireName = r'LinkContinuityPhotoRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LinkContinuityPhotoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'photo_id';
    yield serializers.serialize(
      object.photoId,
      specifiedType: const FullType(String),
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
    LinkContinuityPhotoRequest object, {
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
    required LinkContinuityPhotoRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'photo_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.photoId = valueDes;
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
  LinkContinuityPhotoRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LinkContinuityPhotoRequestBuilder();
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
