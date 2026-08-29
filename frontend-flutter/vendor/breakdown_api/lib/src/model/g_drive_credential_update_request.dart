// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/g_drive_credential_request.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'g_drive_credential_update_request.g.dart';

/// GDriveCredentialUpdateRequest
///
/// Properties:
/// * [clientId]
/// * [clientSecret]
/// * [refreshToken]
/// * [rootFolderId]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class GDriveCredentialUpdateRequest
    implements
        GDriveCredentialRequest,
        Built<GDriveCredentialUpdateRequest,
            GDriveCredentialUpdateRequestBuilder> {
  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  GDriveCredentialUpdateRequest._();

  factory GDriveCredentialUpdateRequest(
          [void updates(GDriveCredentialUpdateRequestBuilder b)]) =
      _$GDriveCredentialUpdateRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GDriveCredentialUpdateRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GDriveCredentialUpdateRequest> get serializer =>
      _$GDriveCredentialUpdateRequestSerializer();
}

class _$GDriveCredentialUpdateRequestSerializer
    implements PrimitiveSerializer<GDriveCredentialUpdateRequest> {
  @override
  final Iterable<Type> types = const [
    GDriveCredentialUpdateRequest,
    _$GDriveCredentialUpdateRequest
  ];

  @override
  final String wireName = r'GDriveCredentialUpdateRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GDriveCredentialUpdateRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'client_secret';
    yield serializers.serialize(
      object.clientSecret,
      specifiedType: const FullType(String),
    );
    if (object.rootFolderId != null) {
      yield r'root_folder_id';
      yield serializers.serialize(
        object.rootFolderId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'client_id';
    yield serializers.serialize(
      object.clientId,
      specifiedType: const FullType(String),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
    yield r'refresh_token';
    yield serializers.serialize(
      object.refreshToken,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GDriveCredentialUpdateRequest object, {
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
    required GDriveCredentialUpdateRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'client_secret':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientSecret = valueDes;
          break;
        case r'root_folder_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.rootFolderId = valueDes;
          break;
        case r'client_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientId = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.version = valueDes;
          break;
        case r'refresh_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.refreshToken = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GDriveCredentialUpdateRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GDriveCredentialUpdateRequestBuilder();
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
