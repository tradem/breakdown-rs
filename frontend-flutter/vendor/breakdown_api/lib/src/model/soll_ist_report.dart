// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/soll_ist_diff_row.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'soll_ist_report.g.dart';

/// The overall Soll-Ist report.
///
/// Properties:
/// * [isFinal]
/// * [rows]
@BuiltValue()
abstract class SollIstReport
    implements Built<SollIstReport, SollIstReportBuilder> {
  @BuiltValueField(wireName: r'is_final')
  bool get isFinal;

  @BuiltValueField(wireName: r'rows')
  BuiltList<SollIstDiffRow> get rows;

  SollIstReport._();

  factory SollIstReport([void updates(SollIstReportBuilder b)]) =
      _$SollIstReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SollIstReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SollIstReport> get serializer =>
      _$SollIstReportSerializer();
}

class _$SollIstReportSerializer implements PrimitiveSerializer<SollIstReport> {
  @override
  final Iterable<Type> types = const [SollIstReport, _$SollIstReport];

  @override
  final String wireName = r'SollIstReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SollIstReport object, {
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
      specifiedType: const FullType(BuiltList, [FullType(SollIstDiffRow)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SollIstReport object, {
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
    required SollIstReportBuilder result,
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
                const FullType(BuiltList, [FullType(SollIstDiffRow)]),
          ) as BuiltList<SollIstDiffRow>;
          result.rows.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SollIstReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SollIstReportBuilder();
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
