// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_provider_budget_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiProviderBudgetView extends AiProviderBudgetView {
  @override
  final double? remaining;

  factory _$AiProviderBudgetView(
          [void Function(AiProviderBudgetViewBuilder)? updates]) =>
      (AiProviderBudgetViewBuilder()..update(updates))._build();

  _$AiProviderBudgetView._({this.remaining}) : super._();
  @override
  AiProviderBudgetView rebuild(
          void Function(AiProviderBudgetViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiProviderBudgetViewBuilder toBuilder() =>
      AiProviderBudgetViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiProviderBudgetView && remaining == other.remaining;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, remaining.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiProviderBudgetView')
          ..add('remaining', remaining))
        .toString();
  }
}

class AiProviderBudgetViewBuilder
    implements Builder<AiProviderBudgetView, AiProviderBudgetViewBuilder> {
  _$AiProviderBudgetView? _$v;

  double? _remaining;
  double? get remaining => _$this._remaining;
  set remaining(double? remaining) => _$this._remaining = remaining;

  AiProviderBudgetViewBuilder() {
    AiProviderBudgetView._defaults(this);
  }

  AiProviderBudgetViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _remaining = $v.remaining;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiProviderBudgetView other) {
    _$v = other as _$AiProviderBudgetView;
  }

  @override
  void update(void Function(AiProviderBudgetViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiProviderBudgetView build() => _build();

  _$AiProviderBudgetView _build() {
    final _$result = _$v ??
        _$AiProviderBudgetView._(
          remaining: remaining,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
