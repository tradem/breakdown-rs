// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'season_membership_dto.g.dart';

/// Season membership DTO — the single source of truth for the client-side AUTHZ-GATE (D2 of the `wire-flutter-oidc-auth` change).  `has_active_costume_role_in_season` is the backend-computed predicate the client must NOT re-implement (CQRS-boundary rule). `capabilities` is derived server-side from the caller's active costume-dept role; the client consumes it with strict parsing (unknown entries reject the DTO).
///
/// Properties:
/// * [capabilities]
/// * [hasActiveCostumeRoleInSeason]
/// * [seasonId]
@BuiltValue()
abstract class SeasonMembershipDto
    implements Built<SeasonMembershipDto, SeasonMembershipDtoBuilder> {
  @BuiltValueField(wireName: r'capabilities')
  BuiltList<String> get capabilities;

  @BuiltValueField(wireName: r'has_active_costume_role_in_season')
  bool get hasActiveCostumeRoleInSeason;

  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  SeasonMembershipDto._();

  factory SeasonMembershipDto([void updates(SeasonMembershipDtoBuilder b)]) =
      _$SeasonMembershipDto;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SeasonMembershipDtoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SeasonMembershipDto> get serializer =>
      _$SeasonMembershipDtoSerializer();
}

class _$SeasonMembershipDtoSerializer
    implements PrimitiveSerializer<SeasonMembershipDto> {
  @override
  final Iterable<Type> types = const [
    SeasonMembershipDto,
    _$SeasonMembershipDto
  ];

  @override
  final String wireName = r'SeasonMembershipDto';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SeasonMembershipDto object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'capabilities';
    yield serializers.serialize(
      object.capabilities,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'has_active_costume_role_in_season';
    yield serializers.serialize(
      object.hasActiveCostumeRoleInSeason,
      specifiedType: const FullType(bool),
    );
    yield r'season_id';
    yield serializers.serialize(
      object.seasonId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SeasonMembershipDto object, {
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
    required SeasonMembershipDtoBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'capabilities':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.capabilities.replace(valueDes);
          break;
        case r'has_active_costume_role_in_season':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasActiveCostumeRoleInSeason = valueDes;
          break;
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seasonId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SeasonMembershipDto deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SeasonMembershipDtoBuilder();
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
