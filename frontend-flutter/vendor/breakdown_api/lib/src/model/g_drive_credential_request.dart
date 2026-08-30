// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'g_drive_credential_request.g.dart';

/// Write-only GDrive credentials. This type intentionally does not implement `Debug` or `Serialize`; it is converted immediately at the API edge into a non-serializable `GDriveCredentialBundle`.
///
/// Properties:
/// * [clientId]
/// * [clientSecret]
/// * [refreshToken]
/// * [rootFolderId]
@BuiltValue(instantiable: false)
abstract class GDriveCredentialRequest {
  @BuiltValueField(wireName: r'client_id')
  String get clientId;

  @BuiltValueField(wireName: r'client_secret')
  String get clientSecret;

  @BuiltValueField(wireName: r'refresh_token')
  String get refreshToken;

  @BuiltValueField(wireName: r'root_folder_id')
  String? get rootFolderId;

  @BuiltValueSerializer(custom: true)
  static Serializer<GDriveCredentialRequest> get serializer =>
      _$GDriveCredentialRequestSerializer();
}

class _$GDriveCredentialRequestSerializer
    implements PrimitiveSerializer<GDriveCredentialRequest> {
  @override
  final Iterable<Type> types = const [GDriveCredentialRequest];

  @override
  final String wireName = r'GDriveCredentialRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GDriveCredentialRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'client_id';
    yield serializers.serialize(
      object.clientId,
      specifiedType: const FullType(String),
    );
    yield r'client_secret';
    yield serializers.serialize(
      object.clientSecret,
      specifiedType: const FullType(String),
    );
    yield r'refresh_token';
    yield serializers.serialize(
      object.refreshToken,
      specifiedType: const FullType(String),
    );
    if (object.rootFolderId != null) {
      yield r'root_folder_id';
      yield serializers.serialize(
        object.rootFolderId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GDriveCredentialRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object,
            specifiedType: specifiedType)
        .toList();
  }

  @override
  GDriveCredentialRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized,
            specifiedType: FullType($GDriveCredentialRequest))
        as $GDriveCredentialRequest;
  }
}

/// a concrete implementation of [GDriveCredentialRequest], since [GDriveCredentialRequest] is not instantiable
@BuiltValue(instantiable: true)
abstract class $GDriveCredentialRequest
    implements
        GDriveCredentialRequest,
        Built<$GDriveCredentialRequest, $GDriveCredentialRequestBuilder> {
  $GDriveCredentialRequest._();

  factory $GDriveCredentialRequest(
          [void Function($GDriveCredentialRequestBuilder)? updates]) =
      _$$GDriveCredentialRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($GDriveCredentialRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$GDriveCredentialRequest> get serializer =>
      _$$GDriveCredentialRequestSerializer();
}

class _$$GDriveCredentialRequestSerializer
    implements PrimitiveSerializer<$GDriveCredentialRequest> {
  @override
  final Iterable<Type> types = const [
    $GDriveCredentialRequest,
    _$$GDriveCredentialRequest
  ];

  @override
  final String wireName = r'$GDriveCredentialRequest';

  @override
  Object serialize(
    Serializers serializers,
    $GDriveCredentialRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object,
        specifiedType: FullType(GDriveCredentialRequest))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GDriveCredentialRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'client_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientId = valueDes;
          break;
        case r'client_secret':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.clientSecret = valueDes;
          break;
        case r'refresh_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.refreshToken = valueDes;
          break;
        case r'root_folder_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.rootFolderId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $GDriveCredentialRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $GDriveCredentialRequestBuilder();
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
