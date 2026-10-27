// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_piece_to_season_request.g.dart';

/// Add a piece to a season's repertoire (issue #534). Idempotent: a season already in the repertoire is a no-op success with the unchanged version.
///
/// Properties:
/// * [seasonId]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class AddPieceToSeasonRequest
    implements Built<AddPieceToSeasonRequest, AddPieceToSeasonRequestBuilder> {
  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  AddPieceToSeasonRequest._();

  factory AddPieceToSeasonRequest(
          [void updates(AddPieceToSeasonRequestBuilder b)]) =
      _$AddPieceToSeasonRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddPieceToSeasonRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddPieceToSeasonRequest> get serializer =>
      _$AddPieceToSeasonRequestSerializer();
}

class _$AddPieceToSeasonRequestSerializer
    implements PrimitiveSerializer<AddPieceToSeasonRequest> {
  @override
  final Iterable<Type> types = const [
    AddPieceToSeasonRequest,
    _$AddPieceToSeasonRequest
  ];

  @override
  final String wireName = r'AddPieceToSeasonRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddPieceToSeasonRequest object, {
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
    AddPieceToSeasonRequest object, {
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
    required AddPieceToSeasonRequestBuilder result,
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
  AddPieceToSeasonRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddPieceToSeasonRequestBuilder();
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
