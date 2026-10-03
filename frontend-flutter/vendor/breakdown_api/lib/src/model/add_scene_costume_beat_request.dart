// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_scene_costume_beat_request.g.dart';

/// Request body for adding a costume beat (issue #546). The `order` is deliberately absent — the aggregate computes it (`max + 1` per character); a client-chosen order would be a race.
///
/// Properties:
/// * [characterId]
/// * [costumeId]
/// * [note] - Optional free-text cue for the wardrobe crew (\"nach dem Telefonat\").
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class AddSceneCostumeBeatRequest
    implements
        Built<AddSceneCostumeBeatRequest, AddSceneCostumeBeatRequestBuilder> {
  @BuiltValueField(wireName: r'character_id')
  String get characterId;

  @BuiltValueField(wireName: r'costume_id')
  String get costumeId;

  /// Optional free-text cue for the wardrobe crew (\"nach dem Telefonat\").
  @BuiltValueField(wireName: r'note')
  String? get note;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  AddSceneCostumeBeatRequest._();

  factory AddSceneCostumeBeatRequest(
          [void updates(AddSceneCostumeBeatRequestBuilder b)]) =
      _$AddSceneCostumeBeatRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddSceneCostumeBeatRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddSceneCostumeBeatRequest> get serializer =>
      _$AddSceneCostumeBeatRequestSerializer();
}

class _$AddSceneCostumeBeatRequestSerializer
    implements PrimitiveSerializer<AddSceneCostumeBeatRequest> {
  @override
  final Iterable<Type> types = const [
    AddSceneCostumeBeatRequest,
    _$AddSceneCostumeBeatRequest
  ];

  @override
  final String wireName = r'AddSceneCostumeBeatRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddSceneCostumeBeatRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_id';
    yield serializers.serialize(
      object.characterId,
      specifiedType: const FullType(String),
    );
    yield r'costume_id';
    yield serializers.serialize(
      object.costumeId,
      specifiedType: const FullType(String),
    );
    if (object.note != null) {
      yield r'note';
      yield serializers.serialize(
        object.note,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AddSceneCostumeBeatRequest object, {
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
    required AddSceneCostumeBeatRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterId = valueDes;
          break;
        case r'costume_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.costumeId = valueDes;
          break;
        case r'note':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.note = valueDes;
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
  AddSceneCostumeBeatRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddSceneCostumeBeatRequestBuilder();
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
