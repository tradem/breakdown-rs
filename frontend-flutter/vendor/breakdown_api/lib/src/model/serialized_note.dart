// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'serialized_note.g.dart';

/// A note as exposed in the read model (flattened for JSON serialisation).
///
/// Properties:
/// * [body]
/// * [id]
@BuiltValue()
abstract class SerializedNote
    implements Built<SerializedNote, SerializedNoteBuilder> {
  @BuiltValueField(wireName: r'body')
  String get body;

  @BuiltValueField(wireName: r'id')
  String get id;

  SerializedNote._();

  factory SerializedNote([void updates(SerializedNoteBuilder b)]) =
      _$SerializedNote;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SerializedNoteBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SerializedNote> get serializer =>
      _$SerializedNoteSerializer();
}

class _$SerializedNoteSerializer
    implements PrimitiveSerializer<SerializedNote> {
  @override
  final Iterable<Type> types = const [SerializedNote, _$SerializedNote];

  @override
  final String wireName = r'SerializedNote';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SerializedNote object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'body';
    yield serializers.serialize(
      object.body,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SerializedNote object, {
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
    required SerializedNoteBuilder result,
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
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SerializedNote deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SerializedNoteBuilder();
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
