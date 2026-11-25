// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/schedule_role_modifier.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'schedule_legend_entry.g.dart';

/// One entry from a shooting schedule's `\"ROLLEN\"` number legend (e.g. `2 = Ben Ahlbeck`, `150 = Zoe (Dummy)` — ADR-041 `D5`/`D6`, issue #960).
///
/// Properties:
/// * [characterName]
/// * [code]
/// * [modifier]
@BuiltValue()
abstract class ScheduleLegendEntry
    implements Built<ScheduleLegendEntry, ScheduleLegendEntryBuilder> {
  @BuiltValueField(wireName: r'character_name')
  String get characterName;

  @BuiltValueField(wireName: r'code')
  String get code;

  @BuiltValueField(wireName: r'modifier')
  ScheduleRoleModifier? get modifier;
  // enum modifierEnum {  none,  dummy,  voice_only,  extra_ot,  };

  ScheduleLegendEntry._();

  factory ScheduleLegendEntry([void updates(ScheduleLegendEntryBuilder b)]) =
      _$ScheduleLegendEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ScheduleLegendEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ScheduleLegendEntry> get serializer =>
      _$ScheduleLegendEntrySerializer();
}

class _$ScheduleLegendEntrySerializer
    implements PrimitiveSerializer<ScheduleLegendEntry> {
  @override
  final Iterable<Type> types = const [
    ScheduleLegendEntry,
    _$ScheduleLegendEntry
  ];

  @override
  final String wireName = r'ScheduleLegendEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ScheduleLegendEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_name';
    yield serializers.serialize(
      object.characterName,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    if (object.modifier != null) {
      yield r'modifier';
      yield serializers.serialize(
        object.modifier,
        specifiedType: const FullType(ScheduleRoleModifier),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ScheduleLegendEntry object, {
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
    required ScheduleLegendEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterName = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'modifier':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(ScheduleRoleModifier),
          ) as ScheduleRoleModifier?;
          if (valueDes == null) continue;
          result.modifier = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ScheduleLegendEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ScheduleLegendEntryBuilder();
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
