// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'add_note_request.g.dart';

/// AddNoteRequest
///
/// Properties:
/// * [body]
/// * [noteId]
@BuiltValue()
abstract class AddNoteRequest
    implements Built<AddNoteRequest, AddNoteRequestBuilder> {
  @BuiltValueField(wireName: r'body')
  String get body;

  @BuiltValueField(wireName: r'note_id')
  String? get noteId;

  AddNoteRequest._();

  factory AddNoteRequest([void updates(AddNoteRequestBuilder b)]) =
      _$AddNoteRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AddNoteRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AddNoteRequest> get serializer =>
      _$AddNoteRequestSerializer();
}

class _$AddNoteRequestSerializer
    implements PrimitiveSerializer<AddNoteRequest> {
  @override
  final Iterable<Type> types = const [AddNoteRequest, _$AddNoteRequest];

  @override
  final String wireName = r'AddNoteRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AddNoteRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'body';
    yield serializers.serialize(
      object.body,
      specifiedType: const FullType(String),
    );
    if (object.noteId != null) {
      yield r'note_id';
      yield serializers.serialize(
        object.noteId,
        specifiedType: const FullType.nullable(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AddNoteRequest object, {
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
    required AddNoteRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'body':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.body = valueDes;
          break;
        case r'note_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.noteId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AddNoteRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AddNoteRequestBuilder();
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
