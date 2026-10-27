// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'piece_detail_view.g.dart';

/// Description element of a piece (e.g. belt, hat, shoes).  Pure description: the category lives on the piece (`PieceView.category_id`), never on the detail.
///
/// Properties:
/// * [id]
/// * [subject] - Free-form per-detail micro-title (e.g. \"Rote Lederjacke\").
/// * [text] - The description.
@BuiltValue()
abstract class PieceDetailView
    implements Built<PieceDetailView, PieceDetailViewBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// Free-form per-detail micro-title (e.g. \"Rote Lederjacke\").
  @BuiltValueField(wireName: r'subject')
  String? get subject;

  /// The description.
  @BuiltValueField(wireName: r'text')
  String get text;

  PieceDetailView._();

  factory PieceDetailView([void updates(PieceDetailViewBuilder b)]) =
      _$PieceDetailView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PieceDetailViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PieceDetailView> get serializer =>
      _$PieceDetailViewSerializer();
}

class _$PieceDetailViewSerializer
    implements PrimitiveSerializer<PieceDetailView> {
  @override
  final Iterable<Type> types = const [PieceDetailView, _$PieceDetailView];

  @override
  final String wireName = r'PieceDetailView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PieceDetailView object, {
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
    PieceDetailView object, {
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
    required PieceDetailViewBuilder result,
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
  PieceDetailView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PieceDetailViewBuilder();
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
