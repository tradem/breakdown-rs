// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_provider_breaker_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiProviderBreakerView extends AiProviderBreakerView {
  @override
  final int consecutiveFailures;
  @override
  final int flapCount;
  @override
  final String model;
  @override
  final LlmProvider provider;
  @override
  final DateTime? retryAt;
  @override
  final ProviderBreakerState state;
  @override
  final bool trialGranted;

  factory _$AiProviderBreakerView(
          [void Function(AiProviderBreakerViewBuilder)? updates]) =>
      (AiProviderBreakerViewBuilder()..update(updates))._build();

  _$AiProviderBreakerView._(
      {required this.consecutiveFailures,
      required this.flapCount,
      required this.model,
      required this.provider,
      this.retryAt,
      required this.state,
      required this.trialGranted})
      : super._();
  @override
  AiProviderBreakerView rebuild(
          void Function(AiProviderBreakerViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiProviderBreakerViewBuilder toBuilder() =>
      AiProviderBreakerViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiProviderBreakerView &&
        consecutiveFailures == other.consecutiveFailures &&
        flapCount == other.flapCount &&
        model == other.model &&
        provider == other.provider &&
        retryAt == other.retryAt &&
        state == other.state &&
        trialGranted == other.trialGranted;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, consecutiveFailures.hashCode);
    _$hash = $jc(_$hash, flapCount.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, retryAt.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, trialGranted.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiProviderBreakerView')
          ..add('consecutiveFailures', consecutiveFailures)
          ..add('flapCount', flapCount)
          ..add('model', model)
          ..add('provider', provider)
          ..add('retryAt', retryAt)
          ..add('state', state)
          ..add('trialGranted', trialGranted))
        .toString();
  }
}

class AiProviderBreakerViewBuilder
    implements Builder<AiProviderBreakerView, AiProviderBreakerViewBuilder> {
  _$AiProviderBreakerView? _$v;

  int? _consecutiveFailures;
  int? get consecutiveFailures => _$this._consecutiveFailures;
  set consecutiveFailures(int? consecutiveFailures) =>
      _$this._consecutiveFailures = consecutiveFailures;

  int? _flapCount;
  int? get flapCount => _$this._flapCount;
  set flapCount(int? flapCount) => _$this._flapCount = flapCount;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  DateTime? _retryAt;
  DateTime? get retryAt => _$this._retryAt;
  set retryAt(DateTime? retryAt) => _$this._retryAt = retryAt;

  ProviderBreakerState? _state;
  ProviderBreakerState? get state => _$this._state;
  set state(ProviderBreakerState? state) => _$this._state = state;

  bool? _trialGranted;
  bool? get trialGranted => _$this._trialGranted;
  set trialGranted(bool? trialGranted) => _$this._trialGranted = trialGranted;

  AiProviderBreakerViewBuilder() {
    AiProviderBreakerView._defaults(this);
  }

  AiProviderBreakerViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _consecutiveFailures = $v.consecutiveFailures;
      _flapCount = $v.flapCount;
      _model = $v.model;
      _provider = $v.provider;
      _retryAt = $v.retryAt;
      _state = $v.state;
      _trialGranted = $v.trialGranted;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiProviderBreakerView other) {
    _$v = other as _$AiProviderBreakerView;
  }

  @override
  void update(void Function(AiProviderBreakerViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiProviderBreakerView build() => _build();

  _$AiProviderBreakerView _build() {
    final _$result = _$v ??
        _$AiProviderBreakerView._(
          consecutiveFailures: BuiltValueNullFieldError.checkNotNull(
              consecutiveFailures,
              r'AiProviderBreakerView',
              'consecutiveFailures'),
          flapCount: BuiltValueNullFieldError.checkNotNull(
              flapCount, r'AiProviderBreakerView', 'flapCount'),
          model: BuiltValueNullFieldError.checkNotNull(
              model, r'AiProviderBreakerView', 'model'),
          provider: BuiltValueNullFieldError.checkNotNull(
              provider, r'AiProviderBreakerView', 'provider'),
          retryAt: retryAt,
          state: BuiltValueNullFieldError.checkNotNull(
              state, r'AiProviderBreakerView', 'state'),
          trialGranted: BuiltValueNullFieldError.checkNotNull(
              trialGranted, r'AiProviderBreakerView', 'trialGranted'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
