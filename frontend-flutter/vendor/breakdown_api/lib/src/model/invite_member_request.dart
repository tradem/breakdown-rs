// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'invite_member_request.g.dart';

/// InviteMemberRequest
///
/// Properties:
/// * [role] - Proposed role for the invited user (pending until they accept).
/// * [userId] - OIDC `sub` of the user to invite to the block.
@BuiltValue()
abstract class InviteMemberRequest
    implements Built<InviteMemberRequest, InviteMemberRequestBuilder> {
  /// Proposed role for the invited user (pending until they accept).
  @BuiltValueField(wireName: r'role')
  Role get role;
  // enum roleEnum {  costume_designer,  wardrobe_supervisor,  costume_assistant,  };

  /// OIDC `sub` of the user to invite to the block.
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  InviteMemberRequest._();

  factory InviteMemberRequest([void updates(InviteMemberRequestBuilder b)]) =
      _$InviteMemberRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InviteMemberRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InviteMemberRequest> get serializer =>
      _$InviteMemberRequestSerializer();
}

class _$InviteMemberRequestSerializer
    implements PrimitiveSerializer<InviteMemberRequest> {
  @override
  final Iterable<Type> types = const [
    InviteMemberRequest,
    _$InviteMemberRequest
  ];

  @override
  final String wireName = r'InviteMemberRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InviteMemberRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(Role),
    );
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    InviteMemberRequest object, {
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
    required InviteMemberRequestBuilder result,
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
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InviteMemberRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InviteMemberRequestBuilder();
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
