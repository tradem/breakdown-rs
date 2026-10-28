// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/draft_outfit_origin.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_candidate.g.dart';

/// One look the script actually supports for a wardrobe gap (design D4).  Surfaced on a gap [`Uncertainty`] so the reviewer can pick a candidate — or leave the scene without an outfit. Deliberately limited to what the preview itself can derive: a continuation of the figure's most recent outfit, or a context look naming the scene's own location. Never an invented option.
///
/// Properties:
/// * [confidence] - Confidence of the underlying decision, `0.0..=1.0`. The pure derivation reports [`super::continuity::CONTINUITY_MIN_CONFIDENCE`] as the floor; the Pass-2 runner stamps the probability the model actually reported.
/// * [name] - Display name of the candidate look.
/// * [origin] - Where the candidate comes from (the badge the reviewer sees).
/// * [sourceDraftRef] - The preview row the candidate was derived from.
/// * [sourceSceneNumber] - That row's document scene number, when it carries one.
@BuiltValue()
abstract class DraftOutfitCandidate
    implements Built<DraftOutfitCandidate, DraftOutfitCandidateBuilder> {
  /// Confidence of the underlying decision, `0.0..=1.0`. The pure derivation reports [`super::continuity::CONTINUITY_MIN_CONFIDENCE`] as the floor; the Pass-2 runner stamps the probability the model actually reported.
  @BuiltValueField(wireName: r'confidence')
  double get confidence;

  /// Display name of the candidate look.
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Where the candidate comes from (the badge the reviewer sees).
  @BuiltValueField(wireName: r'origin')
  DraftOutfitOrigin get origin;
  // enum originEnum {  explicit_quote,  derived,  continued_from_scene,  inferred_from_context,  };

  /// The preview row the candidate was derived from.
  @BuiltValueField(wireName: r'source_draft_ref')
  String get sourceDraftRef;

  /// That row's document scene number, when it carries one.
  @BuiltValueField(wireName: r'source_scene_number')
  int? get sourceSceneNumber;

  DraftOutfitCandidate._();

  factory DraftOutfitCandidate([void updates(DraftOutfitCandidateBuilder b)]) =
      _$DraftOutfitCandidate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitCandidateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfitCandidate> get serializer =>
      _$DraftOutfitCandidateSerializer();
}

class _$DraftOutfitCandidateSerializer
    implements PrimitiveSerializer<DraftOutfitCandidate> {
  @override
  final Iterable<Type> types = const [
    DraftOutfitCandidate,
    _$DraftOutfitCandidate
  ];

  @override
  final String wireName = r'DraftOutfitCandidate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfitCandidate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'confidence';
    yield serializers.serialize(
      object.confidence,
      specifiedType: const FullType(double),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'origin';
    yield serializers.serialize(
      object.origin,
      specifiedType: const FullType(DraftOutfitOrigin),
    );
    yield r'source_draft_ref';
    yield serializers.serialize(
      object.sourceDraftRef,
      specifiedType: const FullType(String),
    );
    if (object.sourceSceneNumber != null) {
      yield r'source_scene_number';
      yield serializers.serialize(
        object.sourceSceneNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftOutfitCandidate object, {
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
    required DraftOutfitCandidateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'confidence':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.confidence = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'origin':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DraftOutfitOrigin),
          ) as DraftOutfitOrigin;
          result.origin = valueDes;
          break;
        case r'source_draft_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceDraftRef = valueDes;
          break;
        case r'source_scene_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sourceSceneNumber = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftOutfitCandidate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitCandidateBuilder();
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
