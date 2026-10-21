// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'link_shooting_day_response.g.dart';

/// The result of one shooting-day link (issue #706): how many scene links moved onto the target day and how many `scene_shoot` pairs were planned there. A pair already existing on the target is not counted again.
///
/// Properties:
/// * [linkedScenes]
/// * [plannedSceneShoots]
@BuiltValue()
abstract class LinkShootingDayResponse
    implements Built<LinkShootingDayResponse, LinkShootingDayResponseBuilder> {
  @BuiltValueField(wireName: r'linked_scenes')
  int get linkedScenes;

  @BuiltValueField(wireName: r'planned_scene_shoots')
  int get plannedSceneShoots;

  LinkShootingDayResponse._();

  factory LinkShootingDayResponse(
          [void updates(LinkShootingDayResponseBuilder b)]) =
      _$LinkShootingDayResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(LinkShootingDayResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<LinkShootingDayResponse> get serializer =>
      _$LinkShootingDayResponseSerializer();
}

class _$LinkShootingDayResponseSerializer
    implements PrimitiveSerializer<LinkShootingDayResponse> {
  @override
  final Iterable<Type> types = const [
    LinkShootingDayResponse,
    _$LinkShootingDayResponse
  ];

  @override
  final String wireName = r'LinkShootingDayResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    LinkShootingDayResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'linked_scenes';
    yield serializers.serialize(
      object.linkedScenes,
      specifiedType: const FullType(int),
    );
    yield r'planned_scene_shoots';
    yield serializers.serialize(
      object.plannedSceneShoots,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    LinkShootingDayResponse object, {
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
    required LinkShootingDayResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'linked_scenes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.linkedScenes = valueDes;
          break;
        case r'planned_scene_shoots':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.plannedSceneShoots = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  LinkShootingDayResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = LinkShootingDayResponseBuilder();
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
