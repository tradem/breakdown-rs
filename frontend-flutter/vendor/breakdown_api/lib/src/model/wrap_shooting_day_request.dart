// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'wrap_shooting_day_request.g.dart';

/// WrapShootingDayRequest
///
/// Properties:
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class WrapShootingDayRequest
    implements Built<WrapShootingDayRequest, WrapShootingDayRequestBuilder> {
  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  WrapShootingDayRequest._();

  factory WrapShootingDayRequest(
          [void updates(WrapShootingDayRequestBuilder b)]) =
      _$WrapShootingDayRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WrapShootingDayRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WrapShootingDayRequest> get serializer =>
      _$WrapShootingDayRequestSerializer();
}

class _$WrapShootingDayRequestSerializer
    implements PrimitiveSerializer<WrapShootingDayRequest> {
  @override
  final Iterable<Type> types = const [
    WrapShootingDayRequest,
    _$WrapShootingDayRequest
  ];

  @override
  final String wireName = r'WrapShootingDayRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WrapShootingDayRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WrapShootingDayRequest object, {
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
    required WrapShootingDayRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  WrapShootingDayRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WrapShootingDayRequestBuilder();
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
