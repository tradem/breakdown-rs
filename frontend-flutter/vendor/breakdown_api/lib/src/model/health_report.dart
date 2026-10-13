// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/health_status.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/health_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'health_report.g.dart';

/// Aggregate health report rendered by `GET /v1/health`.
///
/// Properties:
/// * [entries]
/// * [status]
/// * [totalDurationMs]
@BuiltValue()
abstract class HealthReport
    implements Built<HealthReport, HealthReportBuilder> {
  @BuiltValueField(wireName: r'entries')
  BuiltMap<String, HealthEntry> get entries;

  @BuiltValueField(wireName: r'status')
  HealthStatus get status;
  // enum statusEnum {  Healthy,  Degraded,  Unhealthy,  };

  @BuiltValueField(wireName: r'total_duration_ms')
  int get totalDurationMs;

  HealthReport._();

  factory HealthReport([void updates(HealthReportBuilder b)]) = _$HealthReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HealthReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HealthReport> get serializer => _$HealthReportSerializer();
}

class _$HealthReportSerializer implements PrimitiveSerializer<HealthReport> {
  @override
  final Iterable<Type> types = const [HealthReport, _$HealthReport];

  @override
  final String wireName = r'HealthReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HealthReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'entries';
    yield serializers.serialize(
      object.entries,
      specifiedType:
          const FullType(BuiltMap, [FullType(String), FullType(HealthEntry)]),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(HealthStatus),
    );
    yield r'total_duration_ms';
    yield serializers.serialize(
      object.totalDurationMs,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HealthReport object, {
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
    required HealthReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'entries':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(
                BuiltMap, [FullType(String), FullType(HealthEntry)]),
          ) as BuiltMap<String, HealthEntry>;
          result.entries.replace(valueDes);
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(HealthStatus),
          ) as HealthStatus;
          result.status = valueDes;
          break;
        case r'total_duration_ms':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalDurationMs = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HealthReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HealthReportBuilder();
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
