// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/meta_credits_entry.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'meta_credits_response.g.dart';

/// `GET /v1/meta/credits` response (issue #655): deduped LLM co-authors plus the human contributors. LLM entries come first (sorted by name, provider), humans second (sorted by name) — a fixed, deterministic order.
///
/// Properties:
/// * [credits]
@BuiltValue()
abstract class MetaCreditsResponse
    implements Built<MetaCreditsResponse, MetaCreditsResponseBuilder> {
  @BuiltValueField(wireName: r'credits')
  BuiltList<MetaCreditsEntry> get credits;

  MetaCreditsResponse._();

  factory MetaCreditsResponse([void updates(MetaCreditsResponseBuilder b)]) =
      _$MetaCreditsResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetaCreditsResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetaCreditsResponse> get serializer =>
      _$MetaCreditsResponseSerializer();
}

class _$MetaCreditsResponseSerializer
    implements PrimitiveSerializer<MetaCreditsResponse> {
  @override
  final Iterable<Type> types = const [
    MetaCreditsResponse,
    _$MetaCreditsResponse
  ];

  @override
  final String wireName = r'MetaCreditsResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetaCreditsResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'credits';
    yield serializers.serialize(
      object.credits,
      specifiedType: const FullType(BuiltList, [FullType(MetaCreditsEntry)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MetaCreditsResponse object, {
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
    required MetaCreditsResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'credits':
          final valueDes = serializers.deserialize(
            value,
            specifiedType:
                const FullType(BuiltList, [FullType(MetaCreditsEntry)]),
          ) as BuiltList<MetaCreditsEntry>;
          result.credits.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MetaCreditsResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetaCreditsResponseBuilder();
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
