// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/piece_photo_view.dart';
import 'package:breakdown_api/src/model/piece_detail_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'piece_view.g.dart';

/// Complete piece read model, optionally populated with child details/photos.  `photos` merges the piece's directly linked photos with the photos linked to any outfit containing this piece (fitting photos are usually taken at outfit level), deduplicated by photo id.  `updated_at` is sourced from the timestamp of the last applied `PieceEvent`.
///
/// Properties:
/// * [categoryId] - The piece's single category reference. `None` = uncategorised.
/// * [categoryName] - Denormalised category name, resolved by the projector at write time; `None` on a projection miss (dangling reference, best-effort).
/// * [details]
/// * [id]
/// * [name] - Required, non-blank display name.
/// * [notes]
/// * [photos]
/// * [seasonIds] - The piece's season repertoire, populated from `projection_piece_season`. Ordered by season id (deterministic). Empty for a piece not yet filed into any season.
/// * [updatedAt]
/// * [version] - Aggregate version for optimistic-locking round-trips.
@BuiltValue()
abstract class PieceView implements Built<PieceView, PieceViewBuilder> {
  /// The piece's single category reference. `None` = uncategorised.
  @BuiltValueField(wireName: r'category_id')
  String? get categoryId;

  /// Denormalised category name, resolved by the projector at write time; `None` on a projection miss (dangling reference, best-effort).
  @BuiltValueField(wireName: r'category_name')
  String? get categoryName;

  @BuiltValueField(wireName: r'details')
  BuiltList<PieceDetailView> get details;

  @BuiltValueField(wireName: r'id')
  String get id;

  /// Required, non-blank display name.
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'notes')
  String get notes;

  @BuiltValueField(wireName: r'photos')
  BuiltList<PiecePhotoView> get photos;

  /// The piece's season repertoire, populated from `projection_piece_season`. Ordered by season id (deterministic). Empty for a piece not yet filed into any season.
  @BuiltValueField(wireName: r'season_ids')
  BuiltList<String> get seasonIds;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Aggregate version for optimistic-locking round-trips.
  @BuiltValueField(wireName: r'version')
  int get version;

  PieceView._();

  factory PieceView([void updates(PieceViewBuilder b)]) = _$PieceView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PieceViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PieceView> get serializer => _$PieceViewSerializer();
}

class _$PieceViewSerializer implements PrimitiveSerializer<PieceView> {
  @override
  final Iterable<Type> types = const [PieceView, _$PieceView];

  @override
  final String wireName = r'PieceView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PieceView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.categoryId != null) {
      yield r'category_id';
      yield serializers.serialize(
        object.categoryId,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.categoryName != null) {
      yield r'category_name';
      yield serializers.serialize(
        object.categoryName,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'details';
    yield serializers.serialize(
      object.details,
      specifiedType: const FullType(BuiltList, [FullType(PieceDetailView)]),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
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
      specifiedType: const FullType(BuiltList, [FullType(PiecePhotoView)]),
    );
    yield r'season_ids';
    yield serializers.serialize(
      object.seasonIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
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
    PieceView object, {
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
    required PieceViewBuilder result,
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
        case r'category_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.categoryName = valueDes;
          break;
        case r'details':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(PieceDetailView)]),
          ) as BuiltList<PieceDetailView>;
          result.details.replace(valueDes);
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
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
                const FullType(BuiltList, [FullType(PiecePhotoView)]),
          ) as BuiltList<PiecePhotoView>;
          result.photos.replace(valueDes);
          break;
        case r'season_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.seasonIds.replace(valueDes);
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
  PieceView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PieceViewBuilder();
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
