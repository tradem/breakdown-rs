// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'shooting_schedule_row.g.dart';

/// ShootingScheduleRow
///
/// Properties:
/// * [date]
/// * [location]
/// * [order]
/// * [rowRef]
/// * [sceneNumber]
/// * [shootingDayLabel]
@BuiltValue()
abstract class ShootingScheduleRow
    implements Built<ShootingScheduleRow, ShootingScheduleRowBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'location')
  String? get location;

  @BuiltValueField(wireName: r'order')
  int? get order;

  @BuiltValueField(wireName: r'row_ref')
  String get rowRef;

  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  @BuiltValueField(wireName: r'shooting_day_label')
  String? get shootingDayLabel;

  ShootingScheduleRow._();

  factory ShootingScheduleRow([void updates(ShootingScheduleRowBuilder b)]) =
      _$ShootingScheduleRow;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShootingScheduleRowBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShootingScheduleRow> get serializer =>
      _$ShootingScheduleRowSerializer();
}

class _$ShootingScheduleRowSerializer
    implements PrimitiveSerializer<ShootingScheduleRow> {
  @override
  final Iterable<Type> types = const [
    ShootingScheduleRow,
    _$ShootingScheduleRow
  ];

  @override
  final String wireName = r'ShootingScheduleRow';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShootingScheduleRow object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType.nullable(Date),
      );
    }
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.order != null) {
      yield r'order';
      yield serializers.serialize(
        object.order,
        specifiedType: const FullType.nullable(int),
      );
    }
    yield r'row_ref';
    yield serializers.serialize(
      object.rowRef,
      specifiedType: const FullType(String),
    );
    if (object.sceneNumber != null) {
      yield r'scene_number';
      yield serializers.serialize(
        object.sceneNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.shootingDayLabel != null) {
      yield r'shooting_day_label';
      yield serializers.serialize(
        object.shootingDayLabel,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ShootingScheduleRow object, {
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
    required ShootingScheduleRowBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.date = valueDes;
          break;
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.location = valueDes;
          break;
        case r'order':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.order = valueDes;
          break;
        case r'row_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.rowRef = valueDes;
          break;
        case r'scene_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sceneNumber = valueDes;
          break;
        case r'shooting_day_label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.shootingDayLabel = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ShootingScheduleRow deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShootingScheduleRowBuilder();
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
