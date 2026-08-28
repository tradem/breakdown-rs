// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_shooting_day_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateShootingDayRequest extends CreateShootingDayRequest {
  @override
  final Date? date;
  @override
  final String episodeId;
  @override
  final String? label;
  @override
  final String orderKey;
  @override
  final ShootingDaySource source_;

  factory _$CreateShootingDayRequest(
          [void Function(CreateShootingDayRequestBuilder)? updates]) =>
      (CreateShootingDayRequestBuilder()..update(updates))._build();

  _$CreateShootingDayRequest._(
      {this.date,
      required this.episodeId,
      this.label,
      required this.orderKey,
      required this.source_})
      : super._();
  @override
  CreateShootingDayRequest rebuild(
          void Function(CreateShootingDayRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateShootingDayRequestBuilder toBuilder() =>
      CreateShootingDayRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateShootingDayRequest &&
        date == other.date &&
        episodeId == other.episodeId &&
        label == other.label &&
        orderKey == other.orderKey &&
        source_ == other.source_;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, orderKey.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateShootingDayRequest')
          ..add('date', date)
          ..add('episodeId', episodeId)
          ..add('label', label)
          ..add('orderKey', orderKey)
          ..add('source_', source_))
        .toString();
  }
}

class CreateShootingDayRequestBuilder
    implements
        Builder<CreateShootingDayRequest, CreateShootingDayRequestBuilder> {
  _$CreateShootingDayRequest? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  String? _episodeId;
  String? get episodeId => _$this._episodeId;
  set episodeId(String? episodeId) => _$this._episodeId = episodeId;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  String? _orderKey;
  String? get orderKey => _$this._orderKey;
  set orderKey(String? orderKey) => _$this._orderKey = orderKey;

  ShootingDaySourceBuilder? _source_;
  ShootingDaySourceBuilder get source_ =>
      _$this._source_ ??= ShootingDaySourceBuilder();
  set source_(ShootingDaySourceBuilder? source_) => _$this._source_ = source_;

  CreateShootingDayRequestBuilder() {
    CreateShootingDayRequest._defaults(this);
  }

  CreateShootingDayRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _episodeId = $v.episodeId;
      _label = $v.label;
      _orderKey = $v.orderKey;
      _source_ = $v.source_.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateShootingDayRequest other) {
    _$v = other as _$CreateShootingDayRequest;
  }

  @override
  void update(void Function(CreateShootingDayRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateShootingDayRequest build() => _build();

  _$CreateShootingDayRequest _build() {
    _$CreateShootingDayRequest _$result;
    try {
      _$result = _$v ??
          _$CreateShootingDayRequest._(
            date: date,
            episodeId: BuiltValueNullFieldError.checkNotNull(
                episodeId, r'CreateShootingDayRequest', 'episodeId'),
            label: label,
            orderKey: BuiltValueNullFieldError.checkNotNull(
                orderKey, r'CreateShootingDayRequest', 'orderKey'),
            source_: source_.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'source_';
        source_.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CreateShootingDayRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
