// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/costume_detail_view.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/costume_photo_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'costume_view.g.dart';

/// Complete costume read model, optionally populated with child details/photos.  `updated_at` is sourced from the timestamp of the last applied `CostumeEvent`.
///
/// Properties:
/// * [characterId]
/// * [details]
/// * [id]
/// * [notes]
/// * [photos]
/// * [updatedAt]
/// * [version] - Aggregate version for optimistic-locking round-trips.
@BuiltValue()
abstract class CostumeView implements Built<CostumeView, CostumeViewBuilder> {
  @BuiltValueField(wireName: r'character_id')
  String? get characterId;

  @BuiltValueField(wireName: r'details')
  BuiltList<CostumeDetailView> get details;

  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'notes')
  String get notes;

  @BuiltValueField(wireName: r'photos')
  BuiltList<CostumePhotoView> get photos;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Aggregate version for optimistic-locking round-trips.
  @BuiltValueField(wireName: r'version')
  int get version;

  CostumeView._();

  factory CostumeView([void updates(CostumeViewBuilder b)]) = _$CostumeView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CostumeViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CostumeView> get serializer => _$CostumeViewSerializer();
}

class _$CostumeViewSerializer implements PrimitiveSerializer<CostumeView> {
  @override
  final Iterable<Type> types = const [CostumeView, _$CostumeView];

  @override
  final String wireName = r'CostumeView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CostumeView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.characterId != null) {
      yield r'character_id';
      yield serializers.serialize(
        object.characterId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'details';
    yield serializers.serialize(
      object.details,
      specifiedType: const FullType(BuiltList, [FullType(CostumeDetailView)]),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'notes';
    yield serializers.serialize(
      object.notes,
      specifiedType: const FullType(String),
    );
    yield r'photos';
    yield serializers.serialize(
      object.photos,
      specifiedType: const FullType(BuiltList, [FullType(CostumePhotoView)]),
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
    CostumeView object, {
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
    required CostumeViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.characterId = valueDes;
          break;
        case r'details':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(CostumeDetailView)]),
          ) as BuiltList<CostumeDetailView>;
          result.details.replace(valueDes);
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.notes = valueDes;
          break;
        case r'photos':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(CostumePhotoView)]),
          ) as BuiltList<CostumePhotoView>;
          result.photos.replace(valueDes);
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
  CostumeView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CostumeViewBuilder();
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
