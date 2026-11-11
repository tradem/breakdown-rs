// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_hold.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ProviderHold extends ProviderHold {
  @override
  final int chunksDone;
  @override
  final DateTime holdDeadline;
  @override
  final String model;
  @override
  final LlmProvider provider;
  @override
  final String reasonCode;
  @override
  final ProviderBreakerState state;
  @override
  final DateTime until;

  factory _$ProviderHold([void Function(ProviderHoldBuilder)? updates]) =>
      (ProviderHoldBuilder()..update(updates))._build();

  _$ProviderHold._(
      {required this.chunksDone,
      required this.holdDeadline,
      required this.model,
      required this.provider,
      required this.reasonCode,
      required this.state,
      required this.until})
      : super._();
  @override
  ProviderHold rebuild(void Function(ProviderHoldBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ProviderHoldBuilder toBuilder() => ProviderHoldBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ProviderHold &&
        chunksDone == other.chunksDone &&
        holdDeadline == other.holdDeadline &&
        model == other.model &&
        provider == other.provider &&
        reasonCode == other.reasonCode &&
        state == other.state &&
        until == other.until;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, chunksDone.hashCode);
    _$hash = $jc(_$hash, holdDeadline.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, reasonCode.hashCode);
    _$hash = $jc(_$hash, state.hashCode);
    _$hash = $jc(_$hash, until.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ProviderHold')
          ..add('chunksDone', chunksDone)
          ..add('holdDeadline', holdDeadline)
          ..add('model', model)
          ..add('provider', provider)
          ..add('reasonCode', reasonCode)
          ..add('state', state)
          ..add('until', until))
        .toString();
  }
}

class ProviderHoldBuilder
    implements Builder<ProviderHold, ProviderHoldBuilder> {
  _$ProviderHold? _$v;

  int? _chunksDone;
  int? get chunksDone => _$this._chunksDone;
  set chunksDone(int? chunksDone) => _$this._chunksDone = chunksDone;

  DateTime? _holdDeadline;
  DateTime? get holdDeadline => _$this._holdDeadline;
  set holdDeadline(DateTime? holdDeadline) =>
      _$this._holdDeadline = holdDeadline;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  String? _reasonCode;
  String? get reasonCode => _$this._reasonCode;
  set reasonCode(String? reasonCode) => _$this._reasonCode = reasonCode;

  ProviderBreakerState? _state;
  ProviderBreakerState? get state => _$this._state;
  set state(ProviderBreakerState? state) => _$this._state = state;

  DateTime? _until;
  DateTime? get until => _$this._until;
  set until(DateTime? until) => _$this._until = until;

  ProviderHoldBuilder() {
    ProviderHold._defaults(this);
  }

  ProviderHoldBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _chunksDone = $v.chunksDone;
      _holdDeadline = $v.holdDeadline;
      _model = $v.model;
      _provider = $v.provider;
      _reasonCode = $v.reasonCode;
      _state = $v.state;
      _until = $v.until;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ProviderHold other) {
    _$v = other as _$ProviderHold;
  }

  @override
  void update(void Function(ProviderHoldBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ProviderHold build() => _build();

  _$ProviderHold _build() {
    final _$result = _$v ??
        _$ProviderHold._(
          chunksDone: BuiltValueNullFieldError.checkNotNull(
              chunksDone, r'ProviderHold', 'chunksDone'),
          holdDeadline: BuiltValueNullFieldError.checkNotNull(
              holdDeadline, r'ProviderHold', 'holdDeadline'),
          model: BuiltValueNullFieldError.checkNotNull(
              model, r'ProviderHold', 'model'),
          provider: BuiltValueNullFieldError.checkNotNull(
              provider, r'ProviderHold', 'provider'),
          reasonCode: BuiltValueNullFieldError.checkNotNull(
              reasonCode, r'ProviderHold', 'reasonCode'),
          state: BuiltValueNullFieldError.checkNotNull(
              state, r'ProviderHold', 'state'),
          until: BuiltValueNullFieldError.checkNotNull(
              until, r'ProviderHold', 'until'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
