// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'soll_ist_diff_row.g.dart';

/// The Soll-Ist-Vergleich diff report for a single scene.
///
/// Properties:
/// * [actualOrder] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [location]
/// * [missing] - `true` when planned but without execution data.
/// * [moved] - `true` when `actual_order` differs from `planned_order`.
/// * [plannedOrder] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [reshotCandidate] - `true` when the same scene_id has a `Shot` record on another day.
/// * [sceneId]
/// * [sceneNumber]
/// * [scriptDay]
/// * [skipped] - `true` when status is `Skipped`.
@BuiltValue()
abstract class SollIstDiffRow
    implements Built<SollIstDiffRow, SollIstDiffRowBuilder> {
  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'actual_order')
  String? get actualOrder;

  @BuiltValueField(wireName: r'location')
  String? get location;

  /// `true` when planned but without execution data.
  @BuiltValueField(wireName: r'missing')
  bool get missing;

  /// `true` when `actual_order` differs from `planned_order`.
  @BuiltValueField(wireName: r'moved')
  bool get moved;

  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'planned_order')
  String? get plannedOrder;

  /// `true` when the same scene_id has a `Shot` record on another day.
  @BuiltValueField(wireName: r'reshot_candidate')
  bool get reshotCandidate;

  @BuiltValueField(wireName: r'scene_id')
  String get sceneId;

  @BuiltValueField(wireName: r'scene_number')
  int? get sceneNumber;

  @BuiltValueField(wireName: r'script_day')
  String? get scriptDay;

  /// `true` when status is `Skipped`.
  @BuiltValueField(wireName: r'skipped')
  bool get skipped;

  SollIstDiffRow._();

  factory SollIstDiffRow([void updates(SollIstDiffRowBuilder b)]) =
      _$SollIstDiffRow;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SollIstDiffRowBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SollIstDiffRow> get serializer =>
      _$SollIstDiffRowSerializer();
}

class _$SollIstDiffRowSerializer
    implements PrimitiveSerializer<SollIstDiffRow> {
  @override
  final Iterable<Type> types = const [SollIstDiffRow, _$SollIstDiffRow];

  @override
  final String wireName = r'SollIstDiffRow';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SollIstDiffRow object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.actualOrder != null) {
      yield r'actual_order';
      yield serializers.serialize(
        object.actualOrder,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.location != null) {
      yield r'location';
      yield serializers.serialize(
        object.location,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'missing';
    yield serializers.serialize(
      object.missing,
      specifiedType: const FullType(bool),
    );
    yield r'moved';
    yield serializers.serialize(
      object.moved,
      specifiedType: const FullType(bool),
    );
    if (object.plannedOrder != null) {
      yield r'planned_order';
      yield serializers.serialize(
        object.plannedOrder,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'reshot_candidate';
    yield serializers.serialize(
      object.reshotCandidate,
      specifiedType: const FullType(bool),
    );
    yield r'scene_id';
    yield serializers.serialize(
      object.sceneId,
      specifiedType: const FullType(String),
    );
    if (object.sceneNumber != null) {
      yield r'scene_number';
      yield serializers.serialize(
        object.sceneNumber,
        specifiedType: const FullType.nullable(int),
      );
    }
    if (object.scriptDay != null) {
      yield r'script_day';
      yield serializers.serialize(
        object.scriptDay,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'skipped';
    yield serializers.serialize(
      object.skipped,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SollIstDiffRow object, {
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
    required SollIstDiffRowBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'actual_order':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.actualOrder = valueDes;
          break;
        case r'location':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.location = valueDes;
          break;
        case r'missing':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.missing = valueDes;
          break;
        case r'moved':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.moved = valueDes;
          break;
        case r'planned_order':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.plannedOrder = valueDes;
          break;
        case r'reshot_candidate':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.reshotCandidate = valueDes;
          break;
        case r'scene_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sceneId = valueDes;
          break;
        case r'scene_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(int),
          ) as int?;
          if (valueDes == null) continue;
          result.sceneNumber = valueDes;
          break;
        case r'script_day':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.scriptDay = valueDes;
          break;
        case r'skipped':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.skipped = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SollIstDiffRow deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SollIstDiffRowBuilder();
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
