// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/outfit_photo_view.dart';
import 'package:breakdown_api/src/model/outfit_piece_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'outfit_view.g.dart';

/// Complete outfit read model.  `season_id` and `character_name` are resolved by the read model through the character join (`projection_outfit.character_id → projection_character`); both are `None` on a projection miss and never block the read.
///
/// Properties:
/// * [characterId]
/// * [characterName]
/// * [id]
/// * [name] - Required, non-blank look name.
/// * [notes]
/// * [photos]
/// * [pieceIds] - Insertion-ordered piece references (parallel to `pieces`).
/// * [pieces]
/// * [seasonId]
/// * [updatedAt]
/// * [variantOf] - `Some(source_outfit_id)` when this outfit was forked as a variant.
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class OutfitView implements Built<OutfitView, OutfitViewBuilder> {
  @BuiltValueField(wireName: r'character_id')
  String get characterId;

  @BuiltValueField(wireName: r'character_name')
  String? get characterName;

  @BuiltValueField(wireName: r'id')
  String get id;

  /// Required, non-blank look name.
  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'notes')
  String get notes;

  @BuiltValueField(wireName: r'photos')
  BuiltList<OutfitPhotoView> get photos;

  /// Insertion-ordered piece references (parallel to `pieces`).
  @BuiltValueField(wireName: r'piece_ids')
  BuiltList<String> get pieceIds;

  @BuiltValueField(wireName: r'pieces')
  BuiltList<OutfitPieceView> get pieces;

  @BuiltValueField(wireName: r'season_id')
  String? get seasonId;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// `Some(source_outfit_id)` when this outfit was forked as a variant.
  @BuiltValueField(wireName: r'variant_of')
  String? get variantOf;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  OutfitView._();

  factory OutfitView([void updates(OutfitViewBuilder b)]) = _$OutfitView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OutfitViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OutfitView> get serializer => _$OutfitViewSerializer();
}

class _$OutfitViewSerializer implements PrimitiveSerializer<OutfitView> {
  @override
  final Iterable<Type> types = const [OutfitView, _$OutfitView];

  @override
  final String wireName = r'OutfitView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OutfitView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'character_id';
    yield serializers.serialize(
      object.characterId,
      specifiedType: const FullType(String),
    );
    if (object.characterName != null) {
      yield r'character_name';
      yield serializers.serialize(
        object.characterName,
        specifiedType: const FullType.nullable(String),
      );
    }
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
      specifiedType: const FullType(BuiltList, [FullType(OutfitPhotoView)]),
    );
    yield r'piece_ids';
    yield serializers.serialize(
      object.pieceIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'pieces';
    yield serializers.serialize(
      object.pieces,
      specifiedType: const FullType(BuiltList, [FullType(OutfitPieceView)]),
    );
    if (object.seasonId != null) {
      yield r'season_id';
      yield serializers.serialize(
        object.seasonId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.variantOf != null) {
      yield r'variant_of';
      yield serializers.serialize(
        object.variantOf,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OutfitView object, {
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
    required OutfitViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'character_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.characterId = valueDes;
          break;
        case r'character_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.characterName = valueDes;
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
                const FullType(BuiltList, [FullType(OutfitPhotoView)]),
          ) as BuiltList<OutfitPhotoView>;
          result.photos.replace(valueDes);
          break;
        case r'piece_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.pieceIds.replace(valueDes);
          break;
        case r'pieces':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(OutfitPieceView)]),
          ) as BuiltList<OutfitPieceView>;
          result.pieces.replace(valueDes);
          break;
        case r'season_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.seasonId = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        case r'variant_of':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.variantOf = valueDes;
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
  OutfitView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OutfitViewBuilder();
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
