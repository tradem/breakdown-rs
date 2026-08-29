// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_shooting_day_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateShootingDayRequest extends UpdateShootingDayRequest {
  @override
  final Date? date;
  @override
  final String? label;
  @override
  final String? orderKey;
  @override
  final int version;

  factory _$UpdateShootingDayRequest(
          [void Function(UpdateShootingDayRequestBuilder)? updates]) =>
      (UpdateShootingDayRequestBuilder()..update(updates))._build();

  _$UpdateShootingDayRequest._(
      {this.date, this.label, this.orderKey, required this.version})
      : super._();
  @override
  UpdateShootingDayRequest rebuild(
          void Function(UpdateShootingDayRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateShootingDayRequestBuilder toBuilder() =>
      UpdateShootingDayRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateShootingDayRequest &&
        date == other.date &&
        label == other.label &&
        orderKey == other.orderKey &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, orderKey.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateShootingDayRequest')
          ..add('date', date)
          ..add('label', label)
          ..add('orderKey', orderKey)
          ..add('version', version))
        .toString();
  }
}

class UpdateShootingDayRequestBuilder
    implements
        Builder<UpdateShootingDayRequest, UpdateShootingDayRequestBuilder> {
  _$UpdateShootingDayRequest? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  String? _orderKey;
  String? get orderKey => _$this._orderKey;
  set orderKey(String? orderKey) => _$this._orderKey = orderKey;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateShootingDayRequestBuilder() {
    UpdateShootingDayRequest._defaults(this);
  }

  UpdateShootingDayRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _label = $v.label;
      _orderKey = $v.orderKey;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateShootingDayRequest other) {
    _$v = other as _$UpdateShootingDayRequest;
  }

  @override
  void update(void Function(UpdateShootingDayRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateShootingDayRequest build() => _build();

  _$UpdateShootingDayRequest _build() {
    final _$result = _$v ??
        _$UpdateShootingDayRequest._(
          date: date,
          label: label,
          orderKey: orderKey,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateShootingDayRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
