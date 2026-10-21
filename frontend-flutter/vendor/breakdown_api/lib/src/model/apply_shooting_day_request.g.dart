// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_shooting_day_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyShootingDayRequest extends ApplyShootingDayRequest {
  @override
  final bool accepted;
  @override
  final String dayRef;

  factory _$ApplyShootingDayRequest(
          [void Function(ApplyShootingDayRequestBuilder)? updates]) =>
      (ApplyShootingDayRequestBuilder()..update(updates))._build();

  _$ApplyShootingDayRequest._({required this.accepted, required this.dayRef})
      : super._();
  @override
  ApplyShootingDayRequest rebuild(
          void Function(ApplyShootingDayRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyShootingDayRequestBuilder toBuilder() =>
      ApplyShootingDayRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyShootingDayRequest &&
        accepted == other.accepted &&
        dayRef == other.dayRef;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, accepted.hashCode);
    _$hash = $jc(_$hash, dayRef.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyShootingDayRequest')
          ..add('accepted', accepted)
          ..add('dayRef', dayRef))
        .toString();
  }
}

class ApplyShootingDayRequestBuilder
    implements
        Builder<ApplyShootingDayRequest, ApplyShootingDayRequestBuilder> {
  _$ApplyShootingDayRequest? _$v;

  bool? _accepted;
  bool? get accepted => _$this._accepted;
  set accepted(bool? accepted) => _$this._accepted = accepted;

  String? _dayRef;
  String? get dayRef => _$this._dayRef;
  set dayRef(String? dayRef) => _$this._dayRef = dayRef;

  ApplyShootingDayRequestBuilder() {
    ApplyShootingDayRequest._defaults(this);
  }

  ApplyShootingDayRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _accepted = $v.accepted;
      _dayRef = $v.dayRef;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyShootingDayRequest other) {
    _$v = other as _$ApplyShootingDayRequest;
  }

  @override
  void update(void Function(ApplyShootingDayRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyShootingDayRequest build() => _build();

  _$ApplyShootingDayRequest _build() {
    final _$result = _$v ??
        _$ApplyShootingDayRequest._(
          accepted: BuiltValueNullFieldError.checkNotNull(
              accepted, r'ApplyShootingDayRequest', 'accepted'),
          dayRef: BuiltValueNullFieldError.checkNotNull(
              dayRef, r'ApplyShootingDayRequest', 'dayRef'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
