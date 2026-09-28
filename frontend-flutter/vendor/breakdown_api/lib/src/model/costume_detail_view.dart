// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'costume_detail_view.g.dart';

/// Detailed costume element (e.g. belt, hat, shoes).  Pure description since issue #543: the category lives on the costume (`CostumeView.category_id`), not on the detail. `subject` + `text` remain.
///
/// Properties:
/// * [id]
/// * [subject] - Free-form per-detail micro-title (e.g. \"Rote Lederjacke\").
/// * [text] - The description (unchanged meaning).
@BuiltValue()
abstract class CostumeDetailView
    implements Built<CostumeDetailView, CostumeDetailViewBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Free-form per-detail micro-title (e.g. \"Rote Lederjacke\").
  @BuiltValueField(wireName: r'subject')
  String? get subject;

  /// The description (unchanged meaning).
  @BuiltValueField(wireName: r'text')
  String get text;

  CostumeDetailView._();

  factory CostumeDetailView([void updates(CostumeDetailViewBuilder b)]) =
      _$CostumeDetailView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostumeDetailViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostumeDetailView> get serializer =>
      _$CostumeDetailViewSerializer();
}

class _$CostumeDetailViewSerializer
    implements PrimitiveSerializer<CostumeDetailView> {
  @override
  final Iterable<Type> types = const [CostumeDetailView, _$CostumeDetailView];

  @override
  final String wireName = r'CostumeDetailView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostumeDetailView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    CostumeDetailView object, {
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
    required CostumeDetailViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  CostumeDetailView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostumeDetailViewBuilder();
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
