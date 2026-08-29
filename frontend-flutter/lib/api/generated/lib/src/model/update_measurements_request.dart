// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/character_measurements.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_measurements_request.g.dart';

/// UpdateMeasurementsRequest
///
/// Properties:
/// * [measurements]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdateMeasurementsRequest
    implements
        Built<UpdateMeasurementsRequest, UpdateMeasurementsRequestBuilder> {
  @BuiltValueField(wireName: r'measurements')
  CharacterMeasurements get measurements;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdateMeasurementsRequest._();

  factory UpdateMeasurementsRequest(
          [void updates(UpdateMeasurementsRequestBuilder b)]) =
      _$UpdateMeasurementsRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateMeasurementsRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateMeasurementsRequest> get serializer =>
      _$UpdateMeasurementsRequestSerializer();
}

class _$UpdateMeasurementsRequestSerializer
    implements PrimitiveSerializer<UpdateMeasurementsRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateMeasurementsRequest,
    _$UpdateMeasurementsRequest
  ];

  @override
  final String wireName = r'UpdateMeasurementsRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateMeasurementsRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'measurements';
    yield serializers.serialize(
      object.measurements,
      specifiedType: const FullType(CharacterMeasurements),
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
    UpdateMeasurementsRequest object, {
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
    required UpdateMeasurementsRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'measurements':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CharacterMeasurements),
          ) as CharacterMeasurements;
          result.measurements.replace(valueDes);
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
  UpdateMeasurementsRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateMeasurementsRequestBuilder();
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
