// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_costume_to_season_request.g.dart';

/// Add a costume to a season's repertoire (issue #534). Idempotent: a season already in the repertoire is a no-op success with the unchanged version.
///
/// Properties:
/// * [seasonId]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class AddCostumeToSeasonRequest
    implements
        Built<AddCostumeToSeasonRequest, AddCostumeToSeasonRequestBuilder> {
  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  AddCostumeToSeasonRequest._();

  factory AddCostumeToSeasonRequest(
          [void updates(AddCostumeToSeasonRequestBuilder b)]) =
      _$AddCostumeToSeasonRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddCostumeToSeasonRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddCostumeToSeasonRequest> get serializer =>
      _$AddCostumeToSeasonRequestSerializer();
}

class _$AddCostumeToSeasonRequestSerializer
    implements PrimitiveSerializer<AddCostumeToSeasonRequest> {
  @override
  final Iterable<Type> types = const [
    AddCostumeToSeasonRequest,
    _$AddCostumeToSeasonRequest
  ];

  @override
  final String wireName = r'AddCostumeToSeasonRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddCostumeToSeasonRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'season_id';
    yield serializers.serialize(
      object.seasonId,
      specifiedType: const FullType(String),
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
    AddCostumeToSeasonRequest object, {
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
    required AddCostumeToSeasonRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seasonId = valueDes;
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
  AddCostumeToSeasonRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddCostumeToSeasonRequestBuilder();
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
