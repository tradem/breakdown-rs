// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of1_continuity.g.dart';

/// Continuity (Anschluss) photo — taken during the shoot.
///
/// Properties:
/// * [costumeId]
/// * [sceneShootId] - Opaque identifier for a `SceneShoot` aggregate.  A `SceneShoot` models the association between a `Scene` and a `ShootingDay`, carrying both planned and actual execution data. Each `(scene_id, shooting_day_id)` pair gets its own stream. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`.
@BuiltValue()
abstract class PhotoBindingOneOf1Continuity
    implements
        Built<PhotoBindingOneOf1Continuity,
            PhotoBindingOneOf1ContinuityBuilder> {
  @BuiltValueField(wireName: r'costume_id')
  String? get costumeId;

  /// Opaque identifier for a `SceneShoot` aggregate.  A `SceneShoot` models the association between a `Scene` and a `ShootingDay`, carrying both planned and actual execution data. Each `(scene_id, shooting_day_id)` pair gets its own stream. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`.
  @BuiltValueField(wireName: r'scene_shoot_id')
  String get sceneShootId;

  PhotoBindingOneOf1Continuity._();

  factory PhotoBindingOneOf1Continuity(
          [void updates(PhotoBindingOneOf1ContinuityBuilder b)]) =
      _$PhotoBindingOneOf1Continuity;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOf1ContinuityBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOf1Continuity> get serializer =>
      _$PhotoBindingOneOf1ContinuitySerializer();
}

class _$PhotoBindingOneOf1ContinuitySerializer
    implements PrimitiveSerializer<PhotoBindingOneOf1Continuity> {
  @override
  final Iterable<Type> types = const [
    PhotoBindingOneOf1Continuity,
    _$PhotoBindingOneOf1Continuity
  ];

  @override
  final String wireName = r'PhotoBindingOneOf1Continuity';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOf1Continuity object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.costumeId != null) {
      yield r'costume_id';
      yield serializers.serialize(
        object.costumeId,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'scene_shoot_id';
    yield serializers.serialize(
      object.sceneShootId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhotoBindingOneOf1Continuity object, {
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
    required PhotoBindingOneOf1ContinuityBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'costume_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.costumeId = valueDes;
          break;
        case r'scene_shoot_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sceneShootId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhotoBindingOneOf1Continuity deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOf1ContinuityBuilder();
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
