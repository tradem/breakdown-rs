// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/contact_info.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_contact_info_request.g.dart';

/// UpdateContactInfoRequest
///
/// Properties:
/// * [contactInfo]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdateContactInfoRequest
    implements
        Built<UpdateContactInfoRequest, UpdateContactInfoRequestBuilder> {
  @BuiltValueField(wireName: r'contact_info')
  ContactInfo get contactInfo;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdateContactInfoRequest._();

  factory UpdateContactInfoRequest(
          [void updates(UpdateContactInfoRequestBuilder b)]) =
      _$UpdateContactInfoRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateContactInfoRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateContactInfoRequest> get serializer =>
      _$UpdateContactInfoRequestSerializer();
}

class _$UpdateContactInfoRequestSerializer
    implements PrimitiveSerializer<UpdateContactInfoRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateContactInfoRequest,
    _$UpdateContactInfoRequest
  ];

  @override
  final String wireName = r'UpdateContactInfoRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateContactInfoRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'contact_info';
    yield serializers.serialize(
      object.contactInfo,
      specifiedType: const FullType(ContactInfo),
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
    UpdateContactInfoRequest object, {
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
    required UpdateContactInfoRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'contact_info':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ContactInfo),
          ) as ContactInfo;
          result.contactInfo.replace(valueDes);
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
  UpdateContactInfoRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateContactInfoRequestBuilder();
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
