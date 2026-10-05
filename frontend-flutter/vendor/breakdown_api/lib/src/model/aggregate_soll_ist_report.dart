// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/aggregate_soll_ist_diff_row.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'aggregate_soll_ist_report.g.dart';

/// The aggregated (season- or episode-scoped) Soll-Ist report (issue #571).  `is_final` is **server-derived** and never recomputed client-side: `true` iff the scope has at least one non-archived shooting day and every one of them has `wrapped_at` set. A scope with zero shooting days therefore reports `false` (never vacuously final) with zero counts — an empty report, not an error.
///
/// Properties:
/// * [isFinal]
/// * [rows]
/// * [totalShootingDays] - Number of non-archived shooting days in the scope.
/// * [wrappedShootingDays] - How many of those days are wrapped (`wrapped_at` set).
@BuiltValue()
abstract class AggregateSollIstReport
    implements Built<AggregateSollIstReport, AggregateSollIstReportBuilder> {
  @BuiltValueField(wireName: r'is_final')
  bool get isFinal;

  @BuiltValueField(wireName: r'rows')
  BuiltList<AggregateSollIstDiffRow> get rows;

  /// Number of non-archived shooting days in the scope.
  @BuiltValueField(wireName: r'total_shooting_days')
  int get totalShootingDays;

  /// How many of those days are wrapped (`wrapped_at` set).
  @BuiltValueField(wireName: r'wrapped_shooting_days')
  int get wrappedShootingDays;

  AggregateSollIstReport._();

  factory AggregateSollIstReport(
          [void updates(AggregateSollIstReportBuilder b)]) =
      _$AggregateSollIstReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AggregateSollIstReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AggregateSollIstReport> get serializer =>
      _$AggregateSollIstReportSerializer();
}

class _$AggregateSollIstReportSerializer
    implements PrimitiveSerializer<AggregateSollIstReport> {
  @override
  final Iterable<Type> types = const [
    AggregateSollIstReport,
    _$AggregateSollIstReport
  ];

  @override
  final String wireName = r'AggregateSollIstReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AggregateSollIstReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'is_final';
    yield serializers.serialize(
      object.isFinal,
      specifiedType: const FullType(bool),
    );
    yield r'rows';
    yield serializers.serialize(
      object.rows,
      specifiedType:
          const FullType(BuiltList, [FullType(AggregateSollIstDiffRow)]),
    );
    yield r'total_shooting_days';
    yield serializers.serialize(
      object.totalShootingDays,
      specifiedType: const FullType(int),
    );
    yield r'wrapped_shooting_days';
    yield serializers.serialize(
      object.wrappedShootingDays,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AggregateSollIstReport object, {
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
    required AggregateSollIstReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'is_final':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isFinal = valueDes;
          break;
        case r'rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(AggregateSollIstDiffRow)]),
          ) as BuiltList<AggregateSollIstDiffRow>;
          result.rows.replace(valueDes);
          break;
        case r'total_shooting_days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.totalShootingDays = valueDes;
          break;
        case r'wrapped_shooting_days':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.wrappedShootingDays = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AggregateSollIstReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AggregateSollIstReportBuilder();
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
