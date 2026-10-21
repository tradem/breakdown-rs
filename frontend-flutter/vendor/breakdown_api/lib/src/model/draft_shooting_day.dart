// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_shooting_day.g.dart';

/// One shooting day of the source script, as the deterministic marker scan (and, as a fallback, the LLM's grounded `script_day`) read it out of the document (issue #706). Production scripts repeat day columns in the scene index (`Tag 1`, `1. Spieltag` — the 294.pdf SCRIPT-REPORT format). Metadata only: it groups preview rows for the reviewer and names the day an apply may create; it never resolves an aggregate id (that is the reviewer's per-group decision).
///
/// Properties:
/// * [label] - The marker's verbatim text (or, for the LLM fallback, the model's `script_day` as written) — display-only. First occurrence wins.
/// * [number] - The day number the marker carried, e.g. `1` for `Tag 1` — the normalized identity that groups scenes filmed on the same day regardless of the marker's spelling.
@BuiltValue()
abstract class DraftShootingDay
    implements Built<DraftShootingDay, DraftShootingDayBuilder> {
  /// The marker's verbatim text (or, for the LLM fallback, the model's `script_day` as written) — display-only. First occurrence wins.
  @BuiltValueField(wireName: r'label')
  String? get label;

  /// The day number the marker carried, e.g. `1` for `Tag 1` — the normalized identity that groups scenes filmed on the same day regardless of the marker's spelling.
  @BuiltValueField(wireName: r'number')
  int? get number;

  DraftShootingDay._();

  factory DraftShootingDay([void updates(DraftShootingDayBuilder b)]) =
      _$DraftShootingDay;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftShootingDayBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftShootingDay> get serializer =>
      _$DraftShootingDaySerializer();
}

class _$DraftShootingDaySerializer
    implements PrimitiveSerializer<DraftShootingDay> {
  @override
  final Iterable<Type> types = const [DraftShootingDay, _$DraftShootingDay];

  @override
  final String wireName = r'DraftShootingDay';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftShootingDay object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.number != null) {
      yield r'number';
      yield serializers.serialize(
        object.number,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftShootingDay object, {
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
    required DraftShootingDayBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.label = valueDes;
          break;
        case r'number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.number = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftShootingDay deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftShootingDayBuilder();
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
