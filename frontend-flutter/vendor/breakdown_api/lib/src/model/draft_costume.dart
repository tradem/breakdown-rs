// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_costume.g.dart';

/// One costume extracted for a character of a draft scene.  Flat by design: the LLM has no domain ids, and the write side must not resolve ids from a read-model projection (CQRS boundary). `character_name` is matched against the same draft scene's `characters`; `source_quote` is the fragment the extraction claims to be based on, which the server verifies against the supplied chunk text before the row may reach the reviewer.
///
/// Properties:
/// * [characterName] - Character the costume belongs to, as written in the script.
/// * [description] - The garment/accessory description, in the script's own wording.
/// * [sourceQuote] - Quoted fragment of the chunk this entry was extracted from.
@BuiltValue()
abstract class DraftCostume
    implements Built<DraftCostume, DraftCostumeBuilder> {
  /// Character the costume belongs to, as written in the script.
  @BuiltValueField(wireName: r'character_name')
  String get characterName;

  /// The garment/accessory description, in the script's own wording.
  @BuiltValueField(wireName: r'description')
  String get description;

  /// Quoted fragment of the chunk this entry was extracted from.
  @BuiltValueField(wireName: r'source_quote')
  String get sourceQuote;

  DraftCostume._();

  factory DraftCostume([void updates(DraftCostumeBuilder b)]) = _$DraftCostume;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftCostumeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftCostume> get serializer => _$DraftCostumeSerializer();
}

class _$DraftCostumeSerializer implements PrimitiveSerializer<DraftCostume> {
  @override
  final Iterable<Type> types = const [DraftCostume, _$DraftCostume];

  @override
  final String wireName = r'DraftCostume';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftCostume object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_name';
    yield serializers.serialize(
      object.characterName,
      specifiedType: const FullType(String),
    );
    yield r'description';
    yield serializers.serialize(
      object.description,
      specifiedType: const FullType(String),
    );
    yield r'source_quote';
    yield serializers.serialize(
      object.sourceQuote,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftCostume object, {
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
    required DraftCostumeBuilder result,
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
        case r'description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.description = valueDes;
          break;
        case r'source_quote':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceQuote = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftCostume deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftCostumeBuilder();
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
