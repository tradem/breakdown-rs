// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'series_membership_dto.g.dart';

/// Series membership DTO — the series-level counterpart of [`SeasonMembershipDto`] for the client-side AUTHZ-GATE mirror of the costume-photo policy (issue #535, ADR-035 B2/S2: photos authorize series-wide, so the client needs a series-level, backend-computed signal).  `has_active_costume_role_in_project` is the backend-computed predicate the client must NOT re-implement (CQRS-boundary rule). `capabilities` reuses the same v1 mapping; the photo gates read the predicate field directly.
///
/// Properties:
/// * [capabilities]
/// * [hasActiveCostumeRoleInSeries]
/// * [projectId]
@BuiltValue()
abstract class SeriesMembershipDto
    implements Built<SeriesMembershipDto, SeriesMembershipDtoBuilder> {
  @BuiltValueField(wireName: r'capabilities')
  BuiltList<String> get capabilities;

  @BuiltValueField(wireName: r'has_active_costume_role_in_series')
  bool get hasActiveCostumeRoleInSeries;

  @BuiltValueField(wireName: r'project_id')
  String get projectId;

  SeriesMembershipDto._();

  factory SeriesMembershipDto([void updates(SeriesMembershipDtoBuilder b)]) =
      _$SeriesMembershipDto;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SeriesMembershipDtoBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SeriesMembershipDto> get serializer =>
      _$SeriesMembershipDtoSerializer();
}

class _$SeriesMembershipDtoSerializer
    implements PrimitiveSerializer<SeriesMembershipDto> {
  @override
  final Iterable<Type> types = const [
    SeriesMembershipDto,
    _$SeriesMembershipDto
  ];

  @override
  final String wireName = r'SeriesMembershipDto';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SeriesMembershipDto object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'capabilities';
    yield serializers.serialize(
      object.capabilities,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'has_active_costume_role_in_series';
    yield serializers.serialize(
      object.hasActiveCostumeRoleInSeries,
      specifiedType: const FullType(bool),
    );
    yield r'project_id';
    yield serializers.serialize(
      object.projectId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SeriesMembershipDto object, {
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
    required SeriesMembershipDtoBuilder result,
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
        case r'has_active_costume_role_in_series':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.hasActiveCostumeRoleInSeries = valueDes;
          break;
        case r'project_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.projectId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SeriesMembershipDto deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SeriesMembershipDtoBuilder();
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
