// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/outfit_continuity_candidate.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'outfit_continuity_selection.g.dart';

/// The reviewer's resolution of ONE wardrobe gap: which of the offered candidates the scene's figure should wear.
///
/// Properties:
/// * [candidate] - The candidate the reviewer picked.
/// * [characterIdentity] - The figure's preview-wide identity, as the gap reported it.
/// * [sceneIndex] - Index of the gap scene in [`ScriptContext::scenes`] — the same index the gap [`Uncertainty`] carries.
@BuiltValue()
abstract class OutfitContinuitySelection
    implements
        Built<OutfitContinuitySelection, OutfitContinuitySelectionBuilder> {
  /// The candidate the reviewer picked.
  @BuiltValueField(wireName: r'candidate')
  OutfitContinuityCandidate get candidate;
  // enum candidateEnum {  continued,  inferred,  };

  /// The figure's preview-wide identity, as the gap reported it.
  @BuiltValueField(wireName: r'character_identity')
  String get characterIdentity;

  /// Index of the gap scene in [`ScriptContext::scenes`] — the same index the gap [`Uncertainty`] carries.
  @BuiltValueField(wireName: r'scene_index')
  int get sceneIndex;

  OutfitContinuitySelection._();

  factory OutfitContinuitySelection(
          [void updates(OutfitContinuitySelectionBuilder b)]) =
      _$OutfitContinuitySelection;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OutfitContinuitySelectionBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OutfitContinuitySelection> get serializer =>
      _$OutfitContinuitySelectionSerializer();
}

class _$OutfitContinuitySelectionSerializer
    implements PrimitiveSerializer<OutfitContinuitySelection> {
  @override
  final Iterable<Type> types = const [
    OutfitContinuitySelection,
    _$OutfitContinuitySelection
  ];

  @override
  final String wireName = r'OutfitContinuitySelection';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OutfitContinuitySelection object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'candidate';
    yield serializers.serialize(
      object.candidate,
      specifiedType: const FullType(OutfitContinuityCandidate),
    );
    yield r'character_identity';
    yield serializers.serialize(
      object.characterIdentity,
      specifiedType: const FullType(String),
    );
    yield r'scene_index';
    yield serializers.serialize(
      object.sceneIndex,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OutfitContinuitySelection object, {
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
    required OutfitContinuitySelectionBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'candidate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(OutfitContinuityCandidate),
          ) as OutfitContinuityCandidate;
          result.candidate = valueDes;
          break;
        case r'character_identity':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterIdentity = valueDes;
          break;
        case r'scene_index':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sceneIndex = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OutfitContinuitySelection deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OutfitContinuitySelectionBuilder();
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
