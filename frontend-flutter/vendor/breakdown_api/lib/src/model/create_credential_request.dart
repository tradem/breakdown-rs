// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_credential_request.g.dart';

/// Generic credential submission kept for non-GDrive providers. GDrive uses the typed write-only request below so its complete bundle is stored as one Vault binding.
///
/// Properties:
/// * [provider]
/// * [secret]
@BuiltValue()
abstract class CreateCredentialRequest
    implements Built<CreateCredentialRequest, CreateCredentialRequestBuilder> {
  @BuiltValueField(wireName: r'provider')
  String get provider;

  @BuiltValueField(wireName: r'secret')
  String get secret;

  CreateCredentialRequest._();

  factory CreateCredentialRequest(
          [void updates(CreateCredentialRequestBuilder b)]) =
      _$CreateCredentialRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateCredentialRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateCredentialRequest> get serializer =>
      _$CreateCredentialRequestSerializer();
}

class _$CreateCredentialRequestSerializer
    implements PrimitiveSerializer<CreateCredentialRequest> {
  @override
  final Iterable<Type> types = const [
    CreateCredentialRequest,
    _$CreateCredentialRequest
  ];

  @override
  final String wireName = r'CreateCredentialRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateCredentialRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(String),
    );
    yield r'secret';
    yield serializers.serialize(
      object.secret,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateCredentialRequest object, {
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
    required CreateCredentialRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'secret':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.secret = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateCredentialRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateCredentialRequestBuilder();
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
