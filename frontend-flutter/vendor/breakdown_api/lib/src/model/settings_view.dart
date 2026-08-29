// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:breakdown_api/src/model/credential_binding_state.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'settings_view.g.dart';

/// SettingsView
///
/// Properties:
/// * [bindingState]
/// * [id]
/// * [provider]
/// * [vaultKeyId]
/// * [vaultVersion]
/// * [version] - Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
@BuiltValue()
abstract class SettingsView
    implements Built<SettingsView, SettingsViewBuilder> {
  @BuiltValueField(wireName: r'binding_state')
  CredentialBindingState get bindingState;
  // enum bindingStateEnum {  active,  revoked,  unreachable,  };

  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'provider')
  String get provider;

  @BuiltValueField(wireName: r'vault_key_id')
  String get vaultKeyId;

  @BuiltValueField(wireName: r'vault_version')
  int get vaultVersion;

  /// Aggregate version for optimistic locking.  The canonical version contract is **1-based**: `AggregateVersion::INITIAL = 1`, and every mutation increments the version by one.  The SierraDB stream version (0-based) is an infrastructure-internal detail. The translation rule is: `domain_version = stream_version + 1` (and inversely `stream_version = domain_version - 1`) which is performed exclusively inside `crates::infra` at the `*Commands` adapter boundary. `core` does not reference `stream_version`, `ExpectedVersion`, or `CurrentVersion`.
  @BuiltValueField(wireName: r'version')
  int get version;

  SettingsView._();

  factory SettingsView([void updates(SettingsViewBuilder b)]) = _$SettingsView;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SettingsViewBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SettingsView> get serializer => _$SettingsViewSerializer();
}

class _$SettingsViewSerializer implements PrimitiveSerializer<SettingsView> {
  @override
  final Iterable<Type> types = const [SettingsView, _$SettingsView];

  @override
  final String wireName = r'SettingsView';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SettingsView object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'binding_state';
    yield serializers.serialize(
      object.bindingState,
      specifiedType: const FullType(CredentialBindingState),
    );
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'provider';
    yield serializers.serialize(
      object.provider,
      specifiedType: const FullType(String),
    );
    yield r'vault_key_id';
    yield serializers.serialize(
      object.vaultKeyId,
      specifiedType: const FullType(String),
    );
    yield r'vault_version';
    yield serializers.serialize(
      object.vaultVersion,
      specifiedType: const FullType(int),
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
    SettingsView object, {
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
    required SettingsViewBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'binding_state':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CredentialBindingState),
          ) as CredentialBindingState;
          result.bindingState = valueDes;
          break;
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'provider':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.provider = valueDes;
          break;
        case r'vault_key_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.vaultKeyId = valueDes;
          break;
        case r'vault_version':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.vaultVersion = valueDes;
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
  SettingsView deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SettingsViewBuilder();
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
