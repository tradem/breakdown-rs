// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/date.dart';
import 'package:breakdown_api/src/model/shooting_day_source.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'shooting_day_view.g.dart';

/// Complete shooting-day read model.  `updated_at` is sourced from the timestamp of the last applied `ShootingDayEvent`, not from the UUIDv7 event id.
///
/// Properties:
/// * [archived]
/// * [date]
/// * [episodeId] - Opaque identifier for an `Episode` aggregate.
/// * [id] - Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
/// * [label]
/// * [orderKey] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [source_]
/// * [updatedAt]
/// * [version] - Aggregate version of the last applied event; echo back in optimistic-locking commands.
/// * [wrappedAt] - When this shooting day was wrapped (finalised). `None` means open.
@BuiltValue()
abstract class ShootingDayView
    implements Built<ShootingDayView, ShootingDayViewBuilder> {
  @BuiltValueField(wireName: r'archived')
  bool get archived;

  @BuiltValueField(wireName: r'date')
  Date? get date;

  /// Opaque identifier for an `Episode` aggregate.
  @BuiltValueField(wireName: r'episode_id')
  String get episodeId;

  /// Opaque identifier for a `ShootingDay` aggregate.  A `ShootingDay` is an Episode-scoped scheduling unit (a Drehtag). It is its own event-sourced aggregate, so it gets a dedicated UUIDv7 opaque id that is never decoded inside `core`.
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'label')
  String? get label;

  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'order_key')
  String get orderKey;

  @BuiltValueField(wireName: r'source')
  ShootingDaySource get source_;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  /// Aggregate version of the last applied event; echo back in optimistic-locking commands.
  @BuiltValueField(wireName: r'version')
  int get version;

  /// When this shooting day was wrapped (finalised). `None` means open.
  @BuiltValueField(wireName: r'wrapped_at')
  DateTime? get wrappedAt;

  ShootingDayView._();

  factory ShootingDayView([void updates(ShootingDayViewBuilder b)]) =
      _$ShootingDayView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ShootingDayViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ShootingDayView> get serializer =>
      _$ShootingDayViewSerializer();
}

class _$ShootingDayViewSerializer
    implements PrimitiveSerializer<ShootingDayView> {
  @override
  final Iterable<Type> types = const [ShootingDayView, _$ShootingDayView];

  @override
  final String wireName = r'ShootingDayView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ShootingDayView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'archived';
    yield serializers.serialize(
      object.archived,
      specifiedType: const FullType(bool),
    );
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType.nullable(Date),
      );
    }
    yield r'episode_id';
    yield serializers.serialize(
      object.episodeId,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'order_key';
    yield serializers.serialize(
      object.orderKey,
      specifiedType: const FullType(String),
    );
    yield r'source';
    yield serializers.serialize(
      object.source_,
      specifiedType: const FullType(ShootingDaySource),
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
    if (object.wrappedAt != null) {
      yield r'wrapped_at';
      yield serializers.serialize(
        object.wrappedAt,
        specifiedType: const FullType.nullable(DateTime),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ShootingDayView object, {
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
    required ShootingDayViewBuilder result,
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
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.date = valueDes;
          break;
        case r'episode_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.episodeId = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'label':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.label = valueDes;
          break;
        case r'order_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.orderKey = valueDes;
          break;
        case r'source':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ShootingDaySource),
          ) as ShootingDaySource;
          result.source_.replace(valueDes);
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
        case r'wrapped_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(DateTime),
          ) as DateTime?;
          if (valueDes == null) continue;
          result.wrappedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ShootingDayView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ShootingDayViewBuilder();
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
