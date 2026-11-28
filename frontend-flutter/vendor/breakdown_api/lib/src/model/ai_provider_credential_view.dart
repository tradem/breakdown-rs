// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/account_probe_status.dart';
import 'package:built_collection/built_collection.dart';
import 'package:breakdown_api/src/model/ai_provider_budget_view.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_provider_credential_view.g.dart';

/// One CREDENTIAL the caller holds for `{provider}` and the models it pays for (issue #1013 review).  A provider can be paid by more than one of the caller's credentials: the assistant pair, a distinct `decision_vault_key_id`, and — since #1013 — a distinct `vision_vault_key_id` whose ACCOUNT serves the page images. They are different accounts even on the same provider, so one verdict cannot answer for all of them; this type is the per-account half of that answer.  No `vault_key_id` crosses the wire (schema hygiene of this module): a credential is identified by the models it pays for and by the `selected` bit.
///
/// Properties:
/// * [budget] - The remaining budget as reported by THIS account.
/// * [credentialConfigured] - Whether this credential could be resolved as an owned Vault binding. A `false` here with a listed model means the reference is stale, foreign or malformed — the state the account verdict cannot express.
/// * [models] - The configured models of `{provider}` this credential pays for, sorted and deduplicated.
/// * [probeStatus] - The account-usability verdict measured with THIS credential.
/// * [selected] - Whether this is the credential `credential_configured`/`probe_status`/ `budget` above describe (exactly one entry carries it when the caller has a credential for this provider).
@BuiltValue()
abstract class AiProviderCredentialView
    implements
        Built<AiProviderCredentialView, AiProviderCredentialViewBuilder> {
  /// The remaining budget as reported by THIS account.
  @BuiltValueField(wireName: r'budget')
  AiProviderBudgetView? get budget;

  /// Whether this credential could be resolved as an owned Vault binding. A `false` here with a listed model means the reference is stale, foreign or malformed — the state the account verdict cannot express.
  @BuiltValueField(wireName: r'credential_configured')
  bool get credentialConfigured;

  /// The configured models of `{provider}` this credential pays for, sorted and deduplicated.
  @BuiltValueField(wireName: r'models')
  BuiltList<String> get models;

  /// The account-usability verdict measured with THIS credential.
  @BuiltValueField(wireName: r'probe_status')
  AccountProbeStatus get probeStatus;
  // enum probeStatusEnum {  usable,  not_usable,  unknown,  };

  /// Whether this is the credential `credential_configured`/`probe_status`/ `budget` above describe (exactly one entry carries it when the caller has a credential for this provider).
  @BuiltValueField(wireName: r'selected')
  bool get selected;

  AiProviderCredentialView._();

  factory AiProviderCredentialView(
          [void updates(AiProviderCredentialViewBuilder b)]) =
      _$AiProviderCredentialView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AiProviderCredentialViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AiProviderCredentialView> get serializer =>
      _$AiProviderCredentialViewSerializer();
}

class _$AiProviderCredentialViewSerializer
    implements PrimitiveSerializer<AiProviderCredentialView> {
  @override
  final Iterable<Type> types = const [
    AiProviderCredentialView,
    _$AiProviderCredentialView
  ];

  @override
  final String wireName = r'AiProviderCredentialView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AiProviderCredentialView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.budget != null) {
      yield r'budget';
      yield serializers.serialize(
        object.budget,
        specifiedType: const FullType.nullable(AiProviderBudgetView),
      );
    }
    yield r'credential_configured';
    yield serializers.serialize(
      object.credentialConfigured,
      specifiedType: const FullType(bool),
    );
    yield r'models';
    yield serializers.serialize(
      object.models,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
    );
    yield r'probe_status';
    yield serializers.serialize(
      object.probeStatus,
      specifiedType: const FullType(AccountProbeStatus),
    );
    yield r'selected';
    yield serializers.serialize(
      object.selected,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AiProviderCredentialView object, {
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
    required AiProviderCredentialViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'budget':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType.nullable(AiProviderBudgetView),
          ) as AiProviderBudgetView?;
          if (valueDes == null) continue;
          result.budget.replace(valueDes);
          break;
        case r'credential_configured':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.credentialConfigured = valueDes;
          break;
        case r'models':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.models.replace(valueDes);
          break;
        case r'probe_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AccountProbeStatus),
          ) as AccountProbeStatus;
          result.probeStatus = valueDes;
          break;
        case r'selected':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.selected = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AiProviderCredentialView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AiProviderCredentialViewBuilder();
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
