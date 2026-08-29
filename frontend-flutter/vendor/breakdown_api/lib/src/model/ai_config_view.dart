// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/document_kind.dart';
import 'package:breakdown_api/src/model/llm_provider.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_config_view.g.dart';

/// Public AI configuration view. It contains only the opaque vault reference, never a key or other secret material.
///
/// Properties:
/// * [assistantModel]
/// * [id]
/// * [imageModel]
/// * [promptKinds]
/// * [provider]
/// * [revoked]
/// * [userId] - Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
/// * [vaultKeyId]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class AiConfigView
    implements Built<AiConfigView, AiConfigViewBuilder> {
  @BuiltValueField(wireName: r'assistant_model')
  String get assistantModel;

  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'image_model')
  String? get imageModel;

  @BuiltValueField(wireName: r'prompt_kinds')
  BuiltList<DocumentKind> get promptKinds;

  @BuiltValueField(wireName: r'provider')
  LlmProvider get provider;
  // enum providerEnum {  openai,  openrouter,  eurouter,  neuralwatt,  opencode-go,  opencode,  ollama,  };

  @BuiltValueField(wireName: r'revoked')
  bool get revoked;

  /// Opaque identifier for a user, wrapping the OIDC `sub` claim.  `UserId` references the authenticated principal without ever decoding, storing, or dereferencing identity attributes in `core`. The backend only trusts the IdP-issued `sub`; account lifecycle lives exclusively in the OIDC provider (ADR-010). Unlike the hierarchy ids, `UserId` is *not* a UUIDv7 — it is the raw string subject the IdP assigns.
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'vault_key_id')
  String get vaultKeyId;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  AiConfigView._();

  factory AiConfigView([void updates(AiConfigViewBuilder b)]) = _$AiConfigView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiConfigViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiConfigView> get serializer => _$AiConfigViewSerializer();
}

class _$AiConfigViewSerializer implements PrimitiveSerializer<AiConfigView> {
  @override
  final Iterable<Type> types = const [AiConfigView, _$AiConfigView];

  @override
  final String wireName = r'AiConfigView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiConfigView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'assistant_model';
    yield serializers.serialize(
      object.assistantModel,
      specifiedType: const FullType(String),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    if (object.imageModel != null) {
      yield r'image_model';
      yield serializers.serialize(
        object.imageModel,
        specifiedType: const FullType.nullable(String),
      );
    }
    yield r'prompt_kinds';
    yield serializers.serialize(
      object.promptKinds,
      specifiedType: const FullType(BuiltList, [FullType(DocumentKind)]),
    );
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(LlmProvider),
    );
    yield r'revoked';
    yield serializers.serialize(
      object.revoked,
      specifiedType: const FullType(bool),
    );
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    yield r'vault_key_id';
    yield serializers.serialize(
      object.vaultKeyId,
      specifiedType: const FullType(String),
    );
    yield r'version';
    yield serializers.serialize(
      object.version,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiConfigView object, {
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
    required AiConfigViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'assistant_model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.assistantModel = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'image_model':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(String),
          ) as String?;
          if (valueDes == null) continue;
          result.imageModel = valueDes;
          break;
        case r'prompt_kinds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DocumentKind)]),
          ) as BuiltList<DocumentKind>;
          result.promptKinds.replace(valueDes);
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(LlmProvider),
          ) as LlmProvider;
          result.provider = valueDes;
          break;
        case r'revoked':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.revoked = valueDes;
          break;
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'vault_key_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.vaultKeyId = valueDes;
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
  AiConfigView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiConfigViewBuilder();
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
