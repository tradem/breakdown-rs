// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/membership_state_kind.dart';
import 'package:breakdown_api/src/model/role.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'membership_view.g.dart';

/// Complete membership read model row for one `(block_id, user_id)` pair.  `joined_at` is the timestamp of the `InvitationAccepted` event, sourced from the event stream (not from aggregate state).
///
/// Properties:
/// * [blockId] - Opaque identifier for a `Block` aggregate.
/// * [joinedAt]
/// * [role]
/// * [state]
/// * [userId] - Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
@BuiltValue()
abstract class MembershipView
    implements Built<MembershipView, MembershipViewBuilder> {
  /// Opaque identifier for a `Block` aggregate.
  @BuiltValueField(wireName: r'block_id')
  String get blockId;

  @BuiltValueField(wireName: r'joined_at')
  DateTime get joinedAt;

  @BuiltValueField(wireName: r'role')
  Role get role;
  // enum roleEnum {  costume_designer,  wardrobe_supervisor,  costume_assistant,  };

  @BuiltValueField(wireName: r'state')
  MembershipStateKind get state;
  // enum stateEnum {  pending,  active,  };

  /// Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  MembershipView._();

  factory MembershipView([void updates(MembershipViewBuilder b)]) =
      _$MembershipView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MembershipViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MembershipView> get serializer =>
      _$MembershipViewSerializer();
}

class _$MembershipViewSerializer
    implements PrimitiveSerializer<MembershipView> {
  @override
  final Iterable<Type> types = const [MembershipView, _$MembershipView];

  @override
  final String wireName = r'MembershipView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MembershipView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'block_id';
    yield serializers.serialize(
      object.blockId,
      specifiedType: const FullType(String),
    );
    yield r'joined_at';
    yield serializers.serialize(
      object.joinedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'role';
    yield serializers.serialize(
      object.role,
      specifiedType: const FullType(Role),
    );
    yield r'state';
    yield serializers.serialize(
      object.state,
      specifiedType: const FullType(MembershipStateKind),
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
    MembershipView object, {
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
    required MembershipViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'block_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.blockId = valueDes;
          break;
        case r'joined_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.joinedAt = valueDes;
          break;
        case r'role':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Role),
          ) as Role;
          result.role = valueDes;
          break;
        case r'state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MembershipStateKind),
          ) as MembershipStateKind;
          result.state = valueDes;
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
  MembershipView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MembershipViewBuilder();
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
