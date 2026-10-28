// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/draft_episode.dart';
import 'package:breakdown_api/src/model/draft_shooting_day.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/decision_rubric.dart';
import 'package:breakdown_api/src/model/draft_outfit.dart';
import 'package:breakdown_api/src/model/draft_character.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_scene.g.dart';

/// DraftScene
///
/// Properties:
/// * [characters] - The figures this row names, each with its extracted role type (issue #677). Backward compatible on the wire: a preview stored before the category existed carries plain name strings, which deserialize to the grounded `MainCast` default via [`deserialize_draft_characters`].
/// * [draftRef]
/// * [episode] - The episode this row belongs to (issue #581). Additive on the wire with a default so previews stored before this field existed still load; `None` applies the row to the explicitly picked target episode.
/// * [location]
/// * [mood]
/// * [outfits] - Outfits worn by this scene's characters (OpenSpec change `ai-import-outfit-and-pieces`). Additive on the wire with a default so previews stored before this field existed still load; a preview written by this version loses the field when read by an older binary (breaking, see the change proposal). The former `costumes` field is gone: its flat `description` cannot express the outfit/piece split.
/// * [sceneNumber]
/// * [sceneScore] - Hybrid quality score of the extracted scene (issue #722), `0.0..=1.0` — calibrated Decision Model probabilities blended with deterministic grounding signals. `None` when no decision model is configured or the best-effort scoring pass failed (honest degradation, never a fabricated value). Additive on the wire.
/// * [scoring] - Structured rubric sub-scores (issue #722) — the reward-signal foundation for the `0.5.x` automatic prompt optimization loop.
/// * [scriptDay]
/// * [shootingDay] - The shooting day this row was extracted for (issue #706). Additive on the wire with a default so previews stored before this field existed still load; `None` leaves the row unscheduled. The deterministic day scan is authoritative; the model's verbatim `script_day` normalizes into this field only when the scan found no marker for the chunk.
/// * [summary]
/// * [synopsisScore] - Hybrid quality score of the TL;DR `summary` (issue #722). `Some(0.0)` when `sanitize_meta_summary` had to rewrite the summary; `None` when the row has no summary (outline-only block) or no scoring pass ran.
@BuiltValue()
abstract class DraftScene implements Built<DraftScene, DraftSceneBuilder> {
  /// The figures this row names, each with its extracted role type (issue #677). Backward compatible on the wire: a preview stored before the category existed carries plain name strings, which deserialize to the grounded `MainCast` default via [`deserialize_draft_characters`].
  @BuiltValueField(wireName: r'characters')
  BuiltList<DraftCharacter>? get characters;

  @BuiltValueField(wireName: r'draft_ref')
  String get draftRef;

  /// The episode this row belongs to (issue #581). Additive on the wire with a default so previews stored before this field existed still load; `None` applies the row to the explicitly picked target episode.
  @BuiltValueField(wireName: r'episode')
  DraftEpisode? get episode;

  @BuiltValueField(wireName: r'location')
  String? get location;

  @BuiltValueField(wireName: r'mood')
  String? get mood;

  /// Outfits worn by this scene's characters (OpenSpec change `ai-import-outfit-and-pieces`). Additive on the wire with a default so previews stored before this field existed still load; a preview written by this version loses the field when read by an older binary (breaking, see the change proposal). The former `costumes` field is gone: its flat `description` cannot express the outfit/piece split.
  @BuiltValueField(wireName: r'outfits')
  BuiltList<DraftOutfit>? get outfits;

  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  /// Hybrid quality score of the extracted scene (issue #722), `0.0..=1.0` — calibrated Decision Model probabilities blended with deterministic grounding signals. `None` when no decision model is configured or the best-effort scoring pass failed (honest degradation, never a fabricated value). Additive on the wire.
  @BuiltValueField(wireName: r'scene_score')
  double? get sceneScore;

  /// Structured rubric sub-scores (issue #722) — the reward-signal foundation for the `0.5.x` automatic prompt optimization loop.
  @BuiltValueField(wireName: r'scoring')
  DecisionRubric? get scoring;

  @BuiltValueField(wireName: r'script_day')
  String? get scriptDay;

  /// The shooting day this row was extracted for (issue #706). Additive on the wire with a default so previews stored before this field existed still load; `None` leaves the row unscheduled. The deterministic day scan is authoritative; the model's verbatim `script_day` normalizes into this field only when the scan found no marker for the chunk.
  @BuiltValueField(wireName: r'shooting_day')
  DraftShootingDay? get shootingDay;

  @BuiltValueField(wireName: r'summary')
  String? get summary;

  /// Hybrid quality score of the TL;DR `summary` (issue #722). `Some(0.0)` when `sanitize_meta_summary` had to rewrite the summary; `None` when the row has no summary (outline-only block) or no scoring pass ran.
  @BuiltValueField(wireName: r'synopsis_score')
  double? get synopsisScore;

  DraftScene._();

  factory DraftScene([void updates(DraftSceneBuilder b)]) = _$DraftScene;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftSceneBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftScene> get serializer => _$DraftSceneSerializer();
}

class _$DraftSceneSerializer implements PrimitiveSerializer<DraftScene> {
  @override
  final Iterable<Type> types = const [DraftScene, _$DraftScene];

  @override
  final String wireName = r'DraftScene';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftScene object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.characters != null) {
      yield r'characters';
      yield serializers.serialize(
        object.characters,
        specifiedType: const FullType(BuiltList, [FullType(DraftCharacter)]),
      );
    }
    yield r'draft_ref';
    yield serializers.serialize(
      object.draftRef,
      specifiedType: const FullType(String),
    );
    if (object.episode != null) {
      yield r'episode';
      yield serializers.serialize(
        object.episode,
        specifiedType: const FullType.nullable(DraftEpisode),
      );
    }
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
    if (object.outfits != null) {
      yield r'outfits';
      yield serializers.serialize(
        object.outfits,
        specifiedType: const FullType(BuiltList, [FullType(DraftOutfit)]),
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
    if (object.scoring != null) {
      yield r'scoring';
      yield serializers.serialize(
        object.scoring,
        specifiedType: const FullType.nullable(DecisionRubric),
      );
    }
    if (object.scriptDay != null) {
      yield r'script_day';
      yield serializers.serialize(
        object.scriptDay,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.shootingDay != null) {
      yield r'shooting_day';
      yield serializers.serialize(
        object.shootingDay,
        specifiedType: const FullType.nullable(DraftShootingDay),
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
    DraftScene object, {
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
    required DraftSceneBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'characters':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(DraftCharacter)]),
          ) as BuiltList<DraftCharacter>?;
          if (valueDes == null) continue;
          result.characters.replace(valueDes);
          break;
        case r'draft_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.draftRef = valueDes;
          break;
        case r'episode':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DraftEpisode),
          ) as DraftEpisode?;
          if (valueDes == null) continue;
          result.episode.replace(valueDes);
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
        case r'outfits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType.nullable(BuiltList, [FullType(DraftOutfit)]),
          ) as BuiltList<DraftOutfit>?;
          if (valueDes == null) continue;
          result.outfits.replace(valueDes);
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
        case r'scoring':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DecisionRubric),
          ) as DecisionRubric?;
          if (valueDes == null) continue;
          result.scoring.replace(valueDes);
          break;
        case r'script_day':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.scriptDay = valueDes;
          break;
        case r'shooting_day':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DraftShootingDay),
          ) as DraftShootingDay?;
          if (valueDes == null) continue;
          result.shootingDay.replace(valueDes);
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
  DraftScene deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftSceneBuilder();
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
