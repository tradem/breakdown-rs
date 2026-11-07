// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'scene_details.g.dart';

/// SceneDetails
///
/// Properties:
/// * [isScheduleSet]
/// * [location]
/// * [mood]
/// * [sceneNumber]
/// * [sceneScore] - Decision-Model quality score of the extracted scene (issue #834, mirrors `DraftScene.scene_score`, issue #722), `0.0..=1.0`. Set once at apply time (the projector writes it on `SceneCreated` and PRESERVES it on `SceneDetailsUpdated` — a later detail edit must not erase the recorded provenance); `None` for manual scenes and for rows whose best-effort scoring pass failed (honest absence, never a fabricated value). Additive on the wire with a serde default per ADR-021 (older events/clients omit the fields). The aggregate validates the range at command time and preserves the values across details updates AND replay — the aggregate state, the events and the projection never diverge on these two fields.
/// * [scriptDay] - Fictional script-chronology day (e.g. \"1. Spieltag\"), distinct from the calendar `ShootingDay.date`. Free-form search index.
/// * [summary] - Free-form scene description/prose summary.
/// * [synopsisScore] - Decision-Model quality score of the TL;DR `summary` (issue #834, mirrors `DraftScene.synopsis_score`, issue #722). Same lifecycle as [`SceneDetails::scene_score`]: written once at apply, preserved on detail updates, `None` = unscored.
@BuiltValue()
abstract class SceneDetails
    implements Built<SceneDetails, SceneDetailsBuilder> {
  @BuiltValueField(wireName: r'is_schedule_set')
  bool get isScheduleSet;

  @BuiltValueField(wireName: r'location')
  String? get location;

  @BuiltValueField(wireName: r'mood')
  String? get mood;

  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  /// Decision-Model quality score of the extracted scene (issue #834, mirrors `DraftScene.scene_score`, issue #722), `0.0..=1.0`. Set once at apply time (the projector writes it on `SceneCreated` and PRESERVES it on `SceneDetailsUpdated` — a later detail edit must not erase the recorded provenance); `None` for manual scenes and for rows whose best-effort scoring pass failed (honest absence, never a fabricated value). Additive on the wire with a serde default per ADR-021 (older events/clients omit the fields). The aggregate validates the range at command time and preserves the values across details updates AND replay — the aggregate state, the events and the projection never diverge on these two fields.
  @BuiltValueField(wireName: r'scene_score')
  double? get sceneScore;

  /// Fictional script-chronology day (e.g. \"1. Spieltag\"), distinct from the calendar `ShootingDay.date`. Free-form search index.
  @BuiltValueField(wireName: r'script_day')
  String? get scriptDay;

  /// Free-form scene description/prose summary.
  @BuiltValueField(wireName: r'summary')
  String? get summary;

  /// Decision-Model quality score of the TL;DR `summary` (issue #834, mirrors `DraftScene.synopsis_score`, issue #722). Same lifecycle as [`SceneDetails::scene_score`]: written once at apply, preserved on detail updates, `None` = unscored.
  @BuiltValueField(wireName: r'synopsis_score')
  double? get synopsisScore;

  SceneDetails._();

  factory SceneDetails([void updates(SceneDetailsBuilder b)]) = _$SceneDetails;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SceneDetailsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SceneDetails> get serializer => _$SceneDetailsSerializer();
}

class _$SceneDetailsSerializer implements PrimitiveSerializer<SceneDetails> {
  @override
  final Iterable<Type> types = const [SceneDetails, _$SceneDetails];

  @override
  final String wireName = r'SceneDetails';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SceneDetails object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'is_schedule_set';
    yield serializers.serialize(
      object.isScheduleSet,
      specifiedType: const FullType(bool),
    );
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.mood != null) {
      yield r'mood';
      yield serializers.serialize(
        object.mood,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.sceneNumber != null) {
      yield r'scene_number';
      yield serializers.serialize(
        object.sceneNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.sceneScore != null) {
      yield r'scene_score';
      yield serializers.serialize(
        object.sceneScore,
        specifiedType: const FullType.nullable(double),
      );
    }
    if (object.scriptDay != null) {
      yield r'script_day';
      yield serializers.serialize(
        object.scriptDay,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.summary != null) {
      yield r'summary';
      yield serializers.serialize(
        object.summary,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.synopsisScore != null) {
      yield r'synopsis_score';
      yield serializers.serialize(
        object.synopsisScore,
        specifiedType: const FullType.nullable(double),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SceneDetails object, {
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
    required SceneDetailsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'is_schedule_set':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isScheduleSet = valueDes;
          break;
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.location = valueDes;
          break;
        case r'mood':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.mood = valueDes;
          break;
        case r'scene_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sceneNumber = valueDes;
          break;
        case r'scene_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.sceneScore = valueDes;
          break;
        case r'script_day':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.scriptDay = valueDes;
          break;
        case r'summary':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.summary = valueDes;
          break;
        case r'synopsis_score':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(double),
          ) as double?;
          if (valueDes == null) continue;
          result.synopsisScore = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SceneDetails deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SceneDetailsBuilder();
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
