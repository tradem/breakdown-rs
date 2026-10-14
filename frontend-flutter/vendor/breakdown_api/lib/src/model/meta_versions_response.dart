// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'meta_versions_response.g.dart';

/// Compile-time versions of the workspace crates meaningful to clients.
///
/// Properties:
/// * [api] - Version of the `api` crate (the served HTTP surface itself).
/// * [core] - Version of the `core` crate (domain logic).
/// * [infra] - Version of the `infra` crate (event store, projections).
@BuiltValue()
abstract class MetaVersionsResponse
    implements Built<MetaVersionsResponse, MetaVersionsResponseBuilder> {
  /// Version of the `api` crate (the served HTTP surface itself).
  @BuiltValueField(wireName: r'api')
  String get api;

  /// Version of the `core` crate (domain logic).
  @BuiltValueField(wireName: r'core')
  String get core;

  /// Version of the `infra` crate (event store, projections).
  @BuiltValueField(wireName: r'infra')
  String get infra;

  MetaVersionsResponse._();

  factory MetaVersionsResponse([void updates(MetaVersionsResponseBuilder b)]) =
      _$MetaVersionsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetaVersionsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetaVersionsResponse> get serializer =>
      _$MetaVersionsResponseSerializer();
}

class _$MetaVersionsResponseSerializer
    implements PrimitiveSerializer<MetaVersionsResponse> {
  @override
  final Iterable<Type> types = const [
    MetaVersionsResponse,
    _$MetaVersionsResponse
  ];

  @override
  final String wireName = r'MetaVersionsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetaVersionsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'api';
    yield serializers.serialize(
      object.api,
      specifiedType: const FullType(String),
    );
    yield r'core';
    yield serializers.serialize(
      object.core,
      specifiedType: const FullType(String),
    );
    yield r'infra';
    yield serializers.serialize(
      object.infra,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MetaVersionsResponse object, {
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
    required MetaVersionsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'api':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.api = valueDes;
          break;
        case r'core':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.core = valueDes;
          break;
        case r'infra':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.infra = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MetaVersionsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetaVersionsResponseBuilder();
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
