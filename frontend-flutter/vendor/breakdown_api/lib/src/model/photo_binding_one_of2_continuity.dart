// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'photo_binding_one_of2_continuity.g.dart';

/// Continuity (Anschluss) photo — taken during the shoot.
///
/// Properties:
/// * [pieceId]
/// * [sceneShootId] - Opaque identifier for a `SceneShoot` aggregate.  A `SceneShoot` models the association between a `Scene` and a `ShootingDay`, carrying both planned and actual execution data. Each `(scene_id, shooting_day_id)` pair gets its own stream. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`.
@BuiltValue()
abstract class PhotoBindingOneOf2Continuity
    implements
        Built<PhotoBindingOneOf2Continuity,
            PhotoBindingOneOf2ContinuityBuilder> {
  @BuiltValueField(wireName: r'piece_id')
  String? get pieceId;

  /// Opaque identifier for a `SceneShoot` aggregate.  A `SceneShoot` models the association between a `Scene` and a `ShootingDay`, carrying both planned and actual execution data. Each `(scene_id, shooting_day_id)` pair gets its own stream. Like the other identifiers it is a UUIDv7 opaque value type never decoded inside `core`.
  @BuiltValueField(wireName: r'scene_shoot_id')
  String get sceneShootId;

  PhotoBindingOneOf2Continuity._();

  factory PhotoBindingOneOf2Continuity(
          [void updates(PhotoBindingOneOf2ContinuityBuilder b)]) =
      _$PhotoBindingOneOf2Continuity;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhotoBindingOneOf2ContinuityBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhotoBindingOneOf2Continuity> get serializer =>
      _$PhotoBindingOneOf2ContinuitySerializer();
}

class _$PhotoBindingOneOf2ContinuitySerializer
    implements PrimitiveSerializer<PhotoBindingOneOf2Continuity> {
  @override
  final Iterable<Type> types = const [
    PhotoBindingOneOf2Continuity,
    _$PhotoBindingOneOf2Continuity
  ];

  @override
  final String wireName = r'PhotoBindingOneOf2Continuity';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhotoBindingOneOf2Continuity object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.pieceId != null) {
      yield r'piece_id';
      yield serializers.serialize(
        object.pieceId,
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
    PhotoBindingOneOf2Continuity object, {
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
    required PhotoBindingOneOf2ContinuityBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'piece_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.pieceId = valueDes;
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
  PhotoBindingOneOf2Continuity deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhotoBindingOneOf2ContinuityBuilder();
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
