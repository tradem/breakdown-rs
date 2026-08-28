// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_block_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateBlockRequest extends CreateBlockRequest {
  @override
  final Date? endDate;
  @override
  final int number;
  @override
  final String seasonId;
  @override
  final String seriesId;
  @override
  final Date? startDate;

  factory _$CreateBlockRequest(
          [void Function(CreateBlockRequestBuilder)? updates]) =>
      (CreateBlockRequestBuilder()..update(updates))._build();

  _$CreateBlockRequest._(
      {this.endDate,
      required this.number,
      required this.seasonId,
      required this.seriesId,
      this.startDate})
      : super._();
  @override
  CreateBlockRequest rebuild(
          void Function(CreateBlockRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateBlockRequestBuilder toBuilder() =>
      CreateBlockRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateBlockRequest &&
        endDate == other.endDate &&
        number == other.number &&
        seasonId == other.seasonId &&
        seriesId == other.seriesId &&
        startDate == other.startDate;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endDate.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jc(_$hash, seriesId.hashCode);
    _$hash = $jc(_$hash, startDate.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateBlockRequest')
          ..add('endDate', endDate)
          ..add('number', number)
          ..add('seasonId', seasonId)
          ..add('seriesId', seriesId)
          ..add('startDate', startDate))
        .toString();
  }
}

class CreateBlockRequestBuilder
    implements Builder<CreateBlockRequest, CreateBlockRequestBuilder> {
  _$CreateBlockRequest? _$v;

  Date? _endDate;
  Date? get endDate => _$this._endDate;
  set endDate(Date? endDate) => _$this._endDate = endDate;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  String? _seriesId;
  String? get seriesId => _$this._seriesId;
  set seriesId(String? seriesId) => _$this._seriesId = seriesId;

  Date? _startDate;
  Date? get startDate => _$this._startDate;
  set startDate(Date? startDate) => _$this._startDate = startDate;

  CreateBlockRequestBuilder() {
    CreateBlockRequest._defaults(this);
  }

  CreateBlockRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endDate = $v.endDate;
      _number = $v.number;
      _seasonId = $v.seasonId;
      _seriesId = $v.seriesId;
      _startDate = $v.startDate;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateBlockRequest other) {
    _$v = other as _$CreateBlockRequest;
  }

  @override
  void update(void Function(CreateBlockRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateBlockRequest build() => _build();

  _$CreateBlockRequest _build() {
    final _$result = _$v ??
        _$CreateBlockRequest._(
          endDate: endDate,
          number: BuiltValueNullFieldError.checkNotNull(
              number, r'CreateBlockRequest', 'number'),
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'CreateBlockRequest', 'seasonId'),
          seriesId: BuiltValueNullFieldError.checkNotNull(
              seriesId, r'CreateBlockRequest', 'seriesId'),
          startDate: startDate,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
