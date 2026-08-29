// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'grant_role_request.g.dart';

/// GrantRoleRequest
///
/// Properties:
/// * [role] - New role for the active member (their prior role is replaced).
@BuiltValue()
abstract class GrantRoleRequest
    implements Built<GrantRoleRequest, GrantRoleRequestBuilder> {
  /// New role for the active member (their prior role is replaced).
  @BuiltValueField(wireName: r'role')
  Role get role;
  // enum roleEnum {  costume_designer,  wardrobe_supervisor,  costume_assistant,  };

  GrantRoleRequest._();

  factory GrantRoleRequest([void updates(GrantRoleRequestBuilder b)]) =
      _$GrantRoleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GrantRoleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GrantRoleRequest> get serializer =>
      _$GrantRoleRequestSerializer();
}

class _$GrantRoleRequestSerializer
    implements PrimitiveSerializer<GrantRoleRequest> {
  @override
  final Iterable<Type> types = const [GrantRoleRequest, _$GrantRoleRequest];

  @override
  final String wireName = r'GrantRoleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GrantRoleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(Role),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GrantRoleRequest object, {
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
    required GrantRoleRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Role),
          ) as Role;
          result.role = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GrantRoleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GrantRoleRequestBuilder();
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
