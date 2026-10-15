// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/character_category.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'draft_character.g.dart';

/// One figure a draft row names, with its extracted role type (issue #677).  The category is **grounded**: `MainCast` only when the document truly does not say otherwise (the prompt classifies from the cast-section headings — \"Darsteller\" / \"Gastrollen\" / \"Statisten\" / \"Komparseren\" — and inline notes). A classification the model is unsure about surfaces as an `Uncertainty` instead of silently shipping a wrong category.
///
/// Properties:
/// * [category] - `serde(default)` so a preview (or a model response) without the field keeps the grounded default — old stored previews load unchanged.
/// * [name] - The name **verbatim** from the script (the same contract as the pre-#677 plain string entries).
@BuiltValue()
abstract class DraftCharacter
    implements Built<DraftCharacter, DraftCharacterBuilder> {
  /// `serde(default)` so a preview (or a model response) without the field keeps the grounded default — old stored previews load unchanged.
  @BuiltValueField(wireName: r'category')
  CharacterCategory? get category;
  // enum categoryEnum {  main_cast,  guest,  extra,  };

  /// The name **verbatim** from the script (the same contract as the pre-#677 plain string entries).
  @BuiltValueField(wireName: r'name')
  String get name;

  DraftCharacter._();

  factory DraftCharacter([void updates(DraftCharacterBuilder b)]) =
      _$DraftCharacter;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DraftCharacterBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DraftCharacter> get serializer =>
      _$DraftCharacterSerializer();
}

class _$DraftCharacterSerializer
    implements PrimitiveSerializer<DraftCharacter> {
  @override
  final Iterable<Type> types = const [DraftCharacter, _$DraftCharacter];

  @override
  final String wireName = r'DraftCharacter';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DraftCharacter object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.category != null) {
      yield r'category';
      yield serializers.serialize(
        object.category,
        specifiedType: const FullType(CharacterCategory),
      );
    }
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DraftCharacter object, {
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
    required DraftCharacterBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(CharacterCategory),
          ) as CharacterCategory?;
          if (valueDes == null) continue;
          result.category = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DraftCharacter deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DraftCharacterBuilder();
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
