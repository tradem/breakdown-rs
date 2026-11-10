// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'my_capabilities_response.g.dart';

/// The caller's global (deployment-scoped) capabilities — the wire shape of [`crate::state::AppState::authorization_policy`]'s two global arms.  Field names are the repository predicates verbatim on purpose: the client consumes them *as* the backend-computed answer (CQRS-boundary rule), so a rename here must be a deliberate wire change, not a cosmetic one.
///
/// Properties:
/// * [hasActiveCredentialRole] - The caller holds an active credential role (`costume_designer` / `costume_assistant`) in **any** block — the settings / AI-configuration management gate.
/// * [hasActiveOpsRole] - The caller holds the ops capability: an active `ops_admin` membership in any block **or** a place on the deployment's `OPS_ADMIN_SUBS` bootstrap allowlist (cold start, issue #409).
@BuiltValue()
abstract class MyCapabilitiesResponse
    implements Built<MyCapabilitiesResponse, MyCapabilitiesResponseBuilder> {
  /// The caller holds an active credential role (`costume_designer` / `costume_assistant`) in **any** block — the settings / AI-configuration management gate.
  @BuiltValueField(wireName: r'has_active_credential_role')
  bool get hasActiveCredentialRole;

  /// The caller holds the ops capability: an active `ops_admin` membership in any block **or** a place on the deployment's `OPS_ADMIN_SUBS` bootstrap allowlist (cold start, issue #409).
  @BuiltValueField(wireName: r'has_active_ops_role')
  bool get hasActiveOpsRole;

  MyCapabilitiesResponse._();

  factory MyCapabilitiesResponse(
          [void updates(MyCapabilitiesResponseBuilder b)]) =
      _$MyCapabilitiesResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MyCapabilitiesResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MyCapabilitiesResponse> get serializer =>
      _$MyCapabilitiesResponseSerializer();
}

class _$MyCapabilitiesResponseSerializer
    implements PrimitiveSerializer<MyCapabilitiesResponse> {
  @override
  final Iterable<Type> types = const [
    MyCapabilitiesResponse,
    _$MyCapabilitiesResponse
  ];

  @override
  final String wireName = r'MyCapabilitiesResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MyCapabilitiesResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'has_active_credential_role';
    yield serializers.serialize(
      object.hasActiveCredentialRole,
      specifiedType: const FullType(bool),
    );
    yield r'has_active_ops_role';
    yield serializers.serialize(
      object.hasActiveOpsRole,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MyCapabilitiesResponse object, {
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
    required MyCapabilitiesResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'has_active_credential_role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasActiveCredentialRole = valueDes;
          break;
        case r'has_active_ops_role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasActiveOpsRole = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MyCapabilitiesResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MyCapabilitiesResponseBuilder();
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
