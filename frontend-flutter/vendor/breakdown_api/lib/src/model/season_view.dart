// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'season_view.g.dart';

/// Complete season read model.  `updated_at` is sourced from the timestamp of the last applied `SeasonEvent`.
///
/// Properties:
/// * [archived] - Terminal lifecycle flag (issue #533): `true` once `SeasonArchived` was applied. Archived seasons keep number + inventory readable.
/// * [id]
/// * [number]
/// * [projectId] - The tenant-level production container this season belongs to (`project_id` on the wire, issue #599).
/// * [title]
/// * [updatedAt]
/// * [version] - Aggregate version for optimistic-locking round-trips.
@BuiltValue()
abstract class SeasonView implements Built<SeasonView, SeasonViewBuilder> {
  /// Terminal lifecycle flag (issue #533): `true` once `SeasonArchived` was applied. Archived seasons keep number + inventory readable.
  @BuiltValueField(wireName: r'archived')
  bool get archived;

  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'number')
  int get number;

  /// The tenant-level production container this season belongs to (`project_id` on the wire, issue #599).
  @BuiltValueField(wireName: r'project_id')
  String get projectId;

  @BuiltValueField(wireName: r'title')
  String? get title;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Aggregate version for optimistic-locking round-trips.
  @BuiltValueField(wireName: r'version')
  int get version;

  SeasonView._();

  factory SeasonView([void updates(SeasonViewBuilder b)]) = _$SeasonView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SeasonViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SeasonView> get serializer => _$SeasonViewSerializer();
}

class _$SeasonViewSerializer implements PrimitiveSerializer<SeasonView> {
  @override
  final Iterable<Type> types = const [SeasonView, _$SeasonView];

  @override
  final String wireName = r'SeasonView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SeasonView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'archived';
    yield serializers.serialize(
      object.archived,
      specifiedType: const FullType(bool),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'number';
    yield serializers.serialize(
      object.number,
      specifiedType: const FullType(int),
    );
    yield r'project_id';
    yield serializers.serialize(
      object.projectId,
      specifiedType: const FullType(String),
    );
    if (object.title != null) {
      yield r'title';
      yield serializers.serialize(
        object.title,
        specifiedType: const FullType.nullable(String),
      );
    }
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
    SeasonView object, {
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
    required SeasonViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'archived':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.archived = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.number = valueDes;
          break;
        case r'project_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.projectId = valueDes;
          break;
        case r'title':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.title = valueDes;
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
  SeasonView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SeasonViewBuilder();
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
