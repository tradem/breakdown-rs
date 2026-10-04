// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'episode_target_one_of1.g.dart';

/// EpisodeTargetOneOf1
///
/// Properties:
/// * [kind]
/// * [name]
/// * [number]
@BuiltValue()
abstract class EpisodeTargetOneOf1
    implements Built<EpisodeTargetOneOf1, EpisodeTargetOneOf1Builder> {
  @BuiltValueField(wireName: r'kind')
  EpisodeTargetOneOf1KindEnum get kind;
  // enum kindEnum {  create,  };

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'number')
  int get number;

  EpisodeTargetOneOf1._();

  factory EpisodeTargetOneOf1([void updates(EpisodeTargetOneOf1Builder b)]) =
      _$EpisodeTargetOneOf1;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(EpisodeTargetOneOf1Builder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<EpisodeTargetOneOf1> get serializer =>
      _$EpisodeTargetOneOf1Serializer();
}

class _$EpisodeTargetOneOf1Serializer
    implements PrimitiveSerializer<EpisodeTargetOneOf1> {
  @override
  final Iterable<Type> types = const [
    EpisodeTargetOneOf1,
    _$EpisodeTargetOneOf1
  ];

  @override
  final String wireName = r'EpisodeTargetOneOf1';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    EpisodeTargetOneOf1 object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(EpisodeTargetOneOf1KindEnum),
    );
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'number';
    yield serializers.serialize(
      object.number,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    EpisodeTargetOneOf1 object, {
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
    required EpisodeTargetOneOf1Builder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(EpisodeTargetOneOf1KindEnum),
          ) as EpisodeTargetOneOf1KindEnum;
          result.kind = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.name = valueDes;
          break;
        case r'number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.number = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  EpisodeTargetOneOf1 deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = EpisodeTargetOneOf1Builder();
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

class EpisodeTargetOneOf1KindEnum extends EnumClass {
  @BuiltValueEnumConst(wireName: r'create')
  static const EpisodeTargetOneOf1KindEnum create =
      _$episodeTargetOneOf1KindEnum_create;

  static Serializer<EpisodeTargetOneOf1KindEnum> get serializer =>
      _$episodeTargetOneOf1KindEnumSerializer;

  const EpisodeTargetOneOf1KindEnum._(String name) : super(name);

  static BuiltSet<EpisodeTargetOneOf1KindEnum> get values =>
      _$episodeTargetOneOf1KindEnumValues;
  static EpisodeTargetOneOf1KindEnum valueOf(String name) =>
      _$episodeTargetOneOf1KindEnumValueOf(name);
}
