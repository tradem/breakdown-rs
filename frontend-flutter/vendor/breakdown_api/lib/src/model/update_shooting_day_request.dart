// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_shooting_day_request.g.dart';

/// Request body for mutating a `ShootingDay`.  Exactly one of `order_key` / `date` / `label` should be set; the handler dispatches the matching command (reorder > reschedule > rename). `date` being `Some(None)` is the explicit \"unschedule\" (clear the calendar date).
///
/// Properties:
/// * [date]
/// * [label]
/// * [orderKey] - A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class UpdateShootingDayRequest
    implements
        Built<UpdateShootingDayRequest, UpdateShootingDayRequestBuilder> {
  @BuiltValueField(wireName: r'date')
  Date? get date;

  @BuiltValueField(wireName: r'label')
  String? get label;

  /// A validated, lexicographically-sortable key used for ordering entities (e.g. `ShootingDay`s within an `Episode`) without renumbering siblings.  The key is a non-empty string over a fixed printable-ASCII alphabet (`!`..`~`, i.e. bytes `33..=126`). It carries **no** ordering semantics of its own beyond raw byte/lexicographic order, which matches the SQL `ORDER BY order_key ASC` semantics of the read model. To insert an entity between two existing siblings, use [`LexicalSortKey::midpoint`], which produces a key strictly between the two in exactly one event.
  @BuiltValueField(wireName: r'order_key')
  String? get orderKey;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  UpdateShootingDayRequest._();

  factory UpdateShootingDayRequest(
          [void updates(UpdateShootingDayRequestBuilder b)]) =
      _$UpdateShootingDayRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateShootingDayRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateShootingDayRequest> get serializer =>
      _$UpdateShootingDayRequestSerializer();
}

class _$UpdateShootingDayRequestSerializer
    implements PrimitiveSerializer<UpdateShootingDayRequest> {
  @override
  final Iterable<Type> types = const [
    UpdateShootingDayRequest,
    _$UpdateShootingDayRequest
  ];

  @override
  final String wireName = r'UpdateShootingDayRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateShootingDayRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.date != null) {
      yield r'date';
      yield serializers.serialize(
        object.date,
        specifiedType: const FullType.nullable(Date),
      );
    }
    if (object.label != null) {
      yield r'label';
      yield serializers.serialize(
        object.label,
        specifiedType: const FullType.nullable(String),
      );
    }
    if (object.orderKey != null) {
      yield r'order_key';
      yield serializers.serialize(
        object.orderKey,
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
    UpdateShootingDayRequest object, {
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
    required UpdateShootingDayRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(Date),
          ) as Date?;
          if (valueDes == null) continue;
          result.date = valueDes;
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
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.orderKey = valueDes;
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
  UpdateShootingDayRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateShootingDayRequestBuilder();
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
