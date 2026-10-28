// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_outfit_provenance.g.dart';

/// The Pass-2 provenance of a look (design D2/D3): how sure the Decision Model was, and — for a continuation — which row the look was read from.  Deliberately a separate field instead of arm data on [`DraftOutfitOrigin`]: the origin must stay a plain wire string so the generated client can decode it (see the enum's docs).
///
/// Properties:
/// * [confidence] - The Decision Model's calibrated probability, `0.0..=1.0`.
/// * [sourceDraftRef] - `draft_ref` of the source preview row ([`DraftScene::draft_ref`]); `Some` only for a continuation.
/// * [sourceSceneNumber] - The source row's document scene number, when it carries one.
@BuiltValue()
abstract class DraftOutfitProvenance
    implements Built<DraftOutfitProvenance, DraftOutfitProvenanceBuilder> {
  /// The Decision Model's calibrated probability, `0.0..=1.0`.
  @BuiltValueField(wireName: r'confidence')
  double get confidence;

  /// `draft_ref` of the source preview row ([`DraftScene::draft_ref`]); `Some` only for a continuation.
  @BuiltValueField(wireName: r'source_draft_ref')
  String? get sourceDraftRef;

  /// The source row's document scene number, when it carries one.
  @BuiltValueField(wireName: r'source_scene_number')
  int? get sourceSceneNumber;

  DraftOutfitProvenance._();

  factory DraftOutfitProvenance(
      [void updates(DraftOutfitProvenanceBuilder b)]) = _$DraftOutfitProvenance;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftOutfitProvenanceBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftOutfitProvenance> get serializer =>
      _$DraftOutfitProvenanceSerializer();
}

class _$DraftOutfitProvenanceSerializer
    implements PrimitiveSerializer<DraftOutfitProvenance> {
  @override
  final Iterable<Type> types = const [
    DraftOutfitProvenance,
    _$DraftOutfitProvenance
  ];

  @override
  final String wireName = r'DraftOutfitProvenance';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftOutfitProvenance object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'confidence';
    yield serializers.serialize(
      object.confidence,
      specifiedType: const FullType(double),
    );
    if (object.sourceDraftRef != null) {
      yield r'source_draft_ref';
      yield serializers.serialize(
        object.sourceDraftRef,
        specifiedType: const FullType.nullable(String),
      );
    }
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
    DraftOutfitProvenance object, {
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
    required DraftOutfitProvenanceBuilder result,
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
        case r'source_draft_ref':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
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
  DraftOutfitProvenance deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftOutfitProvenanceBuilder();
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
