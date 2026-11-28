// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_provider_health_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiProviderHealthView extends AiProviderHealthView {
  @override
  final BuiltList<AiProviderBreakerView> breakers;
  @override
  final AiProviderBudgetView? budget;
  @override
  final bool credentialConfigured;
  @override
  final BuiltList<AiProviderCredentialView>? credentials;
  @override
  final AccountProbeStatus probeStatus;
  @override
  final LlmProvider provider;

  factory _$AiProviderHealthView(
          [void Function(AiProviderHealthViewBuilder)? updates]) =>
      (AiProviderHealthViewBuilder()..update(updates))._build();

  _$AiProviderHealthView._(
      {required this.breakers,
      this.budget,
      required this.credentialConfigured,
      this.credentials,
      required this.probeStatus,
      required this.provider})
      : super._();
  @override
  AiProviderHealthView rebuild(
          void Function(AiProviderHealthViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiProviderHealthViewBuilder toBuilder() =>
      AiProviderHealthViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiProviderHealthView &&
        breakers == other.breakers &&
        budget == other.budget &&
        credentialConfigured == other.credentialConfigured &&
        credentials == other.credentials &&
        probeStatus == other.probeStatus &&
        provider == other.provider;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, breakers.hashCode);
    _$hash = $jc(_$hash, budget.hashCode);
    _$hash = $jc(_$hash, credentialConfigured.hashCode);
    _$hash = $jc(_$hash, credentials.hashCode);
    _$hash = $jc(_$hash, probeStatus.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiProviderHealthView')
          ..add('breakers', breakers)
          ..add('budget', budget)
          ..add('credentialConfigured', credentialConfigured)
          ..add('credentials', credentials)
          ..add('probeStatus', probeStatus)
          ..add('provider', provider))
        .toString();
  }
}

class AiProviderHealthViewBuilder
    implements Builder<AiProviderHealthView, AiProviderHealthViewBuilder> {
  _$AiProviderHealthView? _$v;

  ListBuilder<AiProviderBreakerView>? _breakers;
  ListBuilder<AiProviderBreakerView> get breakers =>
      _$this._breakers ??= ListBuilder<AiProviderBreakerView>();
  set breakers(ListBuilder<AiProviderBreakerView>? breakers) =>
      _$this._breakers = breakers;

  AiProviderBudgetViewBuilder? _budget;
  AiProviderBudgetViewBuilder get budget =>
      _$this._budget ??= AiProviderBudgetViewBuilder();
  set budget(AiProviderBudgetViewBuilder? budget) => _$this._budget = budget;

  bool? _credentialConfigured;
  bool? get credentialConfigured => _$this._credentialConfigured;
  set credentialConfigured(bool? credentialConfigured) =>
      _$this._credentialConfigured = credentialConfigured;

  ListBuilder<AiProviderCredentialView>? _credentials;
  ListBuilder<AiProviderCredentialView> get credentials =>
      _$this._credentials ??= ListBuilder<AiProviderCredentialView>();
  set credentials(ListBuilder<AiProviderCredentialView>? credentials) =>
      _$this._credentials = credentials;

  AccountProbeStatus? _probeStatus;
  AccountProbeStatus? get probeStatus => _$this._probeStatus;
  set probeStatus(AccountProbeStatus? probeStatus) =>
      _$this._probeStatus = probeStatus;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  AiProviderHealthViewBuilder() {
    AiProviderHealthView._defaults(this);
  }

  AiProviderHealthViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _breakers = $v.breakers.toBuilder();
      _budget = $v.budget?.toBuilder();
      _credentialConfigured = $v.credentialConfigured;
      _credentials = $v.credentials?.toBuilder();
      _probeStatus = $v.probeStatus;
      _provider = $v.provider;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiProviderHealthView other) {
    _$v = other as _$AiProviderHealthView;
  }

  @override
  void update(void Function(AiProviderHealthViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiProviderHealthView build() => _build();

  _$AiProviderHealthView _build() {
    _$AiProviderHealthView _$result;
    try {
      _$result = _$v ??
          _$AiProviderHealthView._(
            breakers: breakers.build(),
            budget: _budget?.build(),
            credentialConfigured: BuiltValueNullFieldError.checkNotNull(
                credentialConfigured,
                r'AiProviderHealthView',
                'credentialConfigured'),
            credentials: _credentials?.build(),
            probeStatus: BuiltValueNullFieldError.checkNotNull(
                probeStatus, r'AiProviderHealthView', 'probeStatus'),
            provider: BuiltValueNullFieldError.checkNotNull(
                provider, r'AiProviderHealthView', 'provider'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'breakers';
        breakers.build();
        _$failedField = 'budget';
        _budget?.build();

        _$failedField = 'credentials';
        _credentials?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiProviderHealthView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
