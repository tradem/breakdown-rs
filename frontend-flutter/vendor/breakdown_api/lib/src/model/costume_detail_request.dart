// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'costume_detail_request.g.dart';

/// Wire payload for a costume detail (issue #543): pure description — `subject` + `text`. The category is no longer part of the detail wire contract; it is set on the costume via `POST /costumes/{id}/category`. New details deserialize with `category_id: None` in the domain event.
///
/// Properties:
/// * [id]
/// * [subject]
/// * [text]
@BuiltValue()
abstract class CostumeDetailRequest
    implements Built<CostumeDetailRequest, CostumeDetailRequestBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'subject')
  String? get subject;

  @BuiltValueField(wireName: r'text')
  String get text;

  CostumeDetailRequest._();

  factory CostumeDetailRequest([void updates(CostumeDetailRequestBuilder b)]) =
      _$CostumeDetailRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostumeDetailRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostumeDetailRequest> get serializer =>
      _$CostumeDetailRequestSerializer();
}

class _$CostumeDetailRequestSerializer
    implements PrimitiveSerializer<CostumeDetailRequest> {
  @override
  final Iterable<Type> types = const [
    CostumeDetailRequest,
    _$CostumeDetailRequest
  ];

  @override
  final String wireName = r'CostumeDetailRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostumeDetailRequest object, {
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
    CostumeDetailRequest object, {
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
    required CostumeDetailRequestBuilder result,
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
  CostumeDetailRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostumeDetailRequestBuilder();
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
