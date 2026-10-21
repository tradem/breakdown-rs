// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_shooting_day_request.g.dart';

/// One shooting-day group's reviewer decision on the wire (issue #706). `accepted` creates the day (episode-scoped, `AiExtracted` source) and schedules the group's scene rows onto it; a rejection leaves every row of the group unscheduled.
///
/// Properties:
/// * [accepted]
/// * [dayRef] - The group ref the preview carries on each row (`day:<n>` / `day-l:<label>`).
@BuiltValue()
abstract class ApplyShootingDayRequest
    implements Built<ApplyShootingDayRequest, ApplyShootingDayRequestBuilder> {
  @BuiltValueField(wireName: r'accepted')
  bool get accepted;

  /// The group ref the preview carries on each row (`day:<n>` / `day-l:<label>`).
  @BuiltValueField(wireName: r'day_ref')
  String get dayRef;

  ApplyShootingDayRequest._();

  factory ApplyShootingDayRequest(
          [void updates(ApplyShootingDayRequestBuilder b)]) =
      _$ApplyShootingDayRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ApplyShootingDayRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ApplyShootingDayRequest> get serializer =>
      _$ApplyShootingDayRequestSerializer();
}

class _$ApplyShootingDayRequestSerializer
    implements PrimitiveSerializer<ApplyShootingDayRequest> {
  @override
  final Iterable<Type> types = const [
    ApplyShootingDayRequest,
    _$ApplyShootingDayRequest
  ];

  @override
  final String wireName = r'ApplyShootingDayRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ApplyShootingDayRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'accepted';
    yield serializers.serialize(
      object.accepted,
      specifiedType: const FullType(bool),
    );
    yield r'day_ref';
    yield serializers.serialize(
      object.dayRef,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ApplyShootingDayRequest object, {
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
    required ApplyShootingDayRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'accepted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.accepted = valueDes;
          break;
        case r'day_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.dayRef = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ApplyShootingDayRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ApplyShootingDayRequestBuilder();
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
