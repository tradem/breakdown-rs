// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/shooting_schedule_row.dart';
import 'package:breakdown_api/src/model/schedule_legend_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'shooting_schedule.g.dart';

/// ShootingSchedule
///
/// Properties:
/// * [blockId] - Opaque identifier for a `Block` aggregate.
/// * [castLegend] - Optional numeric cast legend (`\"ROLLEN\"`) keyed by cast code (`\"2\"`, `\"150\"`, `\"1040\"`). Additive on the wire (`#[serde(default)]`) so pre-`[P4]` S3 schedule previews deserialize cleanly (issue #960).
/// * [rows]
@BuiltValue()
abstract class ShootingSchedule
    implements Built<ShootingSchedule, ShootingScheduleBuilder> {
  /// Opaque identifier for a `Block` aggregate.
  @BuiltValueField(wireName: r'block_id')
  String? get blockId;

  /// Optional numeric cast legend (`\"ROLLEN\"`) keyed by cast code (`\"2\"`, `\"150\"`, `\"1040\"`). Additive on the wire (`#[serde(default)]`) so pre-`[P4]` S3 schedule previews deserialize cleanly (issue #960).
  @BuiltValueField(wireName: r'cast_legend')
  BuiltMap<String, ScheduleLegendEntry>? get castLegend;

  @BuiltValueField(wireName: r'rows')
  BuiltList<ShootingScheduleRow> get rows;

  ShootingSchedule._();

  factory ShootingSchedule([void updates(ShootingScheduleBuilder b)]) =
      _$ShootingSchedule;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShootingScheduleBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShootingSchedule> get serializer =>
      _$ShootingScheduleSerializer();
}

class _$ShootingScheduleSerializer
    implements PrimitiveSerializer<ShootingSchedule> {
  @override
  final Iterable<Type> types = const [ShootingSchedule, _$ShootingSchedule];

  @override
  final String wireName = r'ShootingSchedule';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShootingSchedule object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.blockId != null) {
      yield r'block_id';
      yield serializers.serialize(
        object.blockId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.castLegend != null) {
      yield r'cast_legend';
      yield serializers.serialize(
        object.castLegend,
        specifiedType: const FullType(
            BuiltMap, [FullType(String), FullType(ScheduleLegendEntry)]),
      );
    }
    yield r'rows';
    yield serializers.serialize(
      object.rows,
      specifiedType: const FullType(BuiltList, [FullType(ShootingScheduleRow)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ShootingSchedule object, {
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
    required ShootingScheduleBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'block_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.blockId = valueDes;
          break;
        case r'cast_legend':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(
                BuiltMap, [FullType(String), FullType(ScheduleLegendEntry)]),
          ) as BuiltMap<String, ScheduleLegendEntry>?;
          if (valueDes == null) continue;
          result.castLegend.replace(valueDes);
          break;
        case r'rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(ShootingScheduleRow)]),
          ) as BuiltList<ShootingScheduleRow>;
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
  ShootingSchedule deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShootingScheduleBuilder();
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
