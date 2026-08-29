// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'costume_detail.g.dart';

/// CostumeDetail
///
/// Properties:
/// * [categoryId] - Reference to a `CostumeCategory` (season-scoped vocabulary). Optional; `None` until the owning Costume is bound to a Season's character.
/// * [id]
/// * [subject] - Free-form per-detail micro-title (e.g. \"Rote Lederjacke\"). Optional.
/// * [text] - The description (unchanged meaning — never reinterpreted from `subject`).
@BuiltValue()
abstract class CostumeDetail
    implements Built<CostumeDetail, CostumeDetailBuilder> {
  /// Reference to a `CostumeCategory` (season-scoped vocabulary). Optional; `None` until the owning Costume is bound to a Season's character.
  @BuiltValueField(wireName: r'category_id')
  String? get categoryId;

  @BuiltValueField(wireName: r'id')
  String get id;

  /// Free-form per-detail micro-title (e.g. \"Rote Lederjacke\"). Optional.
  @BuiltValueField(wireName: r'subject')
  String? get subject;

  /// The description (unchanged meaning — never reinterpreted from `subject`).
  @BuiltValueField(wireName: r'text')
  String get text;

  CostumeDetail._();

  factory CostumeDetail([void updates(CostumeDetailBuilder b)]) =
      _$CostumeDetail;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostumeDetailBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostumeDetail> get serializer =>
      _$CostumeDetailSerializer();
}

class _$CostumeDetailSerializer implements PrimitiveSerializer<CostumeDetail> {
  @override
  final Iterable<Type> types = const [CostumeDetail, _$CostumeDetail];

  @override
  final String wireName = r'CostumeDetail';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostumeDetail object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.categoryId != null) {
      yield r'category_id';
      yield serializers.serialize(
        object.categoryId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.subject != null) {
      yield r'subject';
      yield serializers.serialize(
        object.subject,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'text';
    yield serializers.serialize(
      object.text,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CostumeDetail object, {
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
    required CostumeDetailBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.categoryId = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'subject':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.subject = valueDes;
          break;
        case r'text':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.text = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CostumeDetail deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostumeDetailBuilder();
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
