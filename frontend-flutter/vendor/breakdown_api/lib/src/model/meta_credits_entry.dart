// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'meta_credits_entry.g.dart';

/// One credit entry (issue #655): LLM co-author or human contributor.  One wire shape for both kinds so the client renders the word cloud from a single payload: `provider` is set (and `roles` empty) for LLM co-authors; `roles` is set (and `provider` null) for humans.
///
/// Properties:
/// * [name] - Display name — the model name (LLM) or the contributor handle (human).
/// * [provider] - Provider/tool for LLM co-authors (e.g. `neuralwatt`); null for humans.
/// * [roles] - Roles for human contributors (e.g. `Developer`); empty for LLMs.
@BuiltValue()
abstract class MetaCreditsEntry
    implements Built<MetaCreditsEntry, MetaCreditsEntryBuilder> {
  /// Display name — the model name (LLM) or the contributor handle (human).
  @BuiltValueField(wireName: r'name')
  String get name;

  /// Provider/tool for LLM co-authors (e.g. `neuralwatt`); null for humans.
  @BuiltValueField(wireName: r'provider')
  String? get provider;

  /// Roles for human contributors (e.g. `Developer`); empty for LLMs.
  @BuiltValueField(wireName: r'roles')
  BuiltList<String> get roles;

  MetaCreditsEntry._();

  factory MetaCreditsEntry([void updates(MetaCreditsEntryBuilder b)]) =
      _$MetaCreditsEntry;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MetaCreditsEntryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MetaCreditsEntry> get serializer =>
      _$MetaCreditsEntrySerializer();
}

class _$MetaCreditsEntrySerializer
    implements PrimitiveSerializer<MetaCreditsEntry> {
  @override
  final Iterable<Type> types = const [MetaCreditsEntry, _$MetaCreditsEntry];

  @override
  final String wireName = r'MetaCreditsEntry';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MetaCreditsEntry object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    if (object.provider != null) {
      yield r'provider';
      yield serializers.serialize(
        object.provider,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'roles';
    yield serializers.serialize(
      object.roles,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    MetaCreditsEntry object, {
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
    required MetaCreditsEntryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.provider = valueDes;
          break;
        case r'roles':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.roles.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MetaCreditsEntry deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MetaCreditsEntryBuilder();
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
