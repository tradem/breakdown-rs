// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_provider_credential_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiProviderCredentialView extends AiProviderCredentialView {
  @override
  final AiProviderBudgetView? budget;
  @override
  final bool credentialConfigured;
  @override
  final BuiltList<String> models;
  @override
  final AccountProbeStatus probeStatus;
  @override
  final bool selected;

  factory _$AiProviderCredentialView(
          [void Function(AiProviderCredentialViewBuilder)? updates]) =>
      (AiProviderCredentialViewBuilder()..update(updates))._build();

  _$AiProviderCredentialView._(
      {this.budget,
      required this.credentialConfigured,
      required this.models,
      required this.probeStatus,
      required this.selected})
      : super._();
  @override
  AiProviderCredentialView rebuild(
          void Function(AiProviderCredentialViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiProviderCredentialViewBuilder toBuilder() =>
      AiProviderCredentialViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiProviderCredentialView &&
        budget == other.budget &&
        credentialConfigured == other.credentialConfigured &&
        models == other.models &&
        probeStatus == other.probeStatus &&
        selected == other.selected;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, budget.hashCode);
    _$hash = $jc(_$hash, credentialConfigured.hashCode);
    _$hash = $jc(_$hash, models.hashCode);
    _$hash = $jc(_$hash, probeStatus.hashCode);
    _$hash = $jc(_$hash, selected.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiProviderCredentialView')
          ..add('budget', budget)
          ..add('credentialConfigured', credentialConfigured)
          ..add('models', models)
          ..add('probeStatus', probeStatus)
          ..add('selected', selected))
        .toString();
  }
}

class AiProviderCredentialViewBuilder
    implements
        Builder<AiProviderCredentialView, AiProviderCredentialViewBuilder> {
  _$AiProviderCredentialView? _$v;

  AiProviderBudgetViewBuilder? _budget;
  AiProviderBudgetViewBuilder get budget =>
      _$this._budget ??= AiProviderBudgetViewBuilder();
  set budget(AiProviderBudgetViewBuilder? budget) => _$this._budget = budget;

  bool? _credentialConfigured;
  bool? get credentialConfigured => _$this._credentialConfigured;
  set credentialConfigured(bool? credentialConfigured) =>
      _$this._credentialConfigured = credentialConfigured;

  ListBuilder<String>? _models;
  ListBuilder<String> get models => _$this._models ??= ListBuilder<String>();
  set models(ListBuilder<String>? models) => _$this._models = models;

  AccountProbeStatus? _probeStatus;
  AccountProbeStatus? get probeStatus => _$this._probeStatus;
  set probeStatus(AccountProbeStatus? probeStatus) =>
      _$this._probeStatus = probeStatus;

  bool? _selected;
  bool? get selected => _$this._selected;
  set selected(bool? selected) => _$this._selected = selected;

  AiProviderCredentialViewBuilder() {
    AiProviderCredentialView._defaults(this);
  }

  AiProviderCredentialViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _budget = $v.budget?.toBuilder();
      _credentialConfigured = $v.credentialConfigured;
      _models = $v.models.toBuilder();
      _probeStatus = $v.probeStatus;
      _selected = $v.selected;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiProviderCredentialView other) {
    _$v = other as _$AiProviderCredentialView;
  }

  @override
  void update(void Function(AiProviderCredentialViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiProviderCredentialView build() => _build();

  _$AiProviderCredentialView _build() {
    _$AiProviderCredentialView _$result;
    try {
      _$result = _$v ??
          _$AiProviderCredentialView._(
            budget: _budget?.build(),
            credentialConfigured: BuiltValueNullFieldError.checkNotNull(
                credentialConfigured,
                r'AiProviderCredentialView',
                'credentialConfigured'),
            models: models.build(),
            probeStatus: BuiltValueNullFieldError.checkNotNull(
                probeStatus, r'AiProviderCredentialView', 'probeStatus'),
            selected: BuiltValueNullFieldError.checkNotNull(
                selected, r'AiProviderCredentialView', 'selected'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'budget';
        _budget?.build();

        _$failedField = 'models';
        models.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiProviderCredentialView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
