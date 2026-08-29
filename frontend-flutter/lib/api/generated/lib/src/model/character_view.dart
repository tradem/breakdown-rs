// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/character_category.dart';
import 'package:breakdown_api/src/model/character_measurements.dart';
import 'package:breakdown_api/src/model/contact_info.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'character_view.g.dart';

/// Complete character read model.  `updated_at` is sourced from the timestamp of the last applied `CharacterEvent`.
///
/// Properties:
/// * [category]
/// * [contact]
/// * [id]
/// * [measurements]
/// * [name]
/// * [seasonId] - Opaque identifier for a `Season` aggregate.
/// * [updatedAt]
/// * [version] - Aggregate version for optimistic-locking round-trips.
@BuiltValue()
abstract class CharacterView
    implements Built<CharacterView, CharacterViewBuilder> {
  @BuiltValueField(wireName: r'category')
  CharacterCategory get category;
  // enum categoryEnum {  main_cast,  guest,  extra,  };

  @BuiltValueField(wireName: r'contact')
  ContactInfo get contact;

  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'measurements')
  CharacterMeasurements get measurements;

  @BuiltValueField(wireName: r'name')
  String get name;

  /// Opaque identifier for a `Season` aggregate.
  @BuiltValueField(wireName: r'season_id')
  String get seasonId;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Aggregate version for optimistic-locking round-trips.
  @BuiltValueField(wireName: r'version')
  int get version;

  CharacterView._();

  factory CharacterView([void updates(CharacterViewBuilder b)]) =
      _$CharacterView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CharacterViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CharacterView> get serializer =>
      _$CharacterViewSerializer();
}

class _$CharacterViewSerializer implements PrimitiveSerializer<CharacterView> {
  @override
  final Iterable<Type> types = const [CharacterView, _$CharacterView];

  @override
  final String wireName = r'CharacterView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CharacterView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'category';
    yield serializers.serialize(
      object.category,
      specifiedType: const FullType(CharacterCategory),
    );
    yield r'contact';
    yield serializers.serialize(
      object.contact,
      specifiedType: const FullType(ContactInfo),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'measurements';
    yield serializers.serialize(
      object.measurements,
      specifiedType: const FullType(CharacterMeasurements),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'season_id';
    yield serializers.serialize(
      object.seasonId,
      specifiedType: const FullType(String),
    );
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CharacterView object, {
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
    required CharacterViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'category':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CharacterCategory),
          ) as CharacterCategory;
          result.category = valueDes;
          break;
        case r'contact':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ContactInfo),
          ) as ContactInfo;
          result.contact.replace(valueDes);
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'measurements':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CharacterMeasurements),
          ) as CharacterMeasurements;
          result.measurements.replace(valueDes);
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.seasonId = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        case r'version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.version = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CharacterView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CharacterViewBuilder();
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
