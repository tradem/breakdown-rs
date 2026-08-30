// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_block_time_span_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateBlockTimeSpanRequest extends UpdateBlockTimeSpanRequest {
  @override
  final Date? endDate;
  @override
  final Date? startDate;
  @override
  final int version;

  factory _$UpdateBlockTimeSpanRequest(
          [void Function(UpdateBlockTimeSpanRequestBuilder)? updates]) =>
      (UpdateBlockTimeSpanRequestBuilder()..update(updates))._build();

  _$UpdateBlockTimeSpanRequest._(
      {this.endDate, this.startDate, required this.version})
      : super._();
  @override
  UpdateBlockTimeSpanRequest rebuild(
          void Function(UpdateBlockTimeSpanRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateBlockTimeSpanRequestBuilder toBuilder() =>
      UpdateBlockTimeSpanRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateBlockTimeSpanRequest &&
        endDate == other.endDate &&
        startDate == other.startDate &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endDate.hashCode);
    _$hash = $jc(_$hash, startDate.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateBlockTimeSpanRequest')
          ..add('endDate', endDate)
          ..add('startDate', startDate)
          ..add('version', version))
        .toString();
  }
}

class UpdateBlockTimeSpanRequestBuilder
    implements
        Builder<UpdateBlockTimeSpanRequest, UpdateBlockTimeSpanRequestBuilder> {
  _$UpdateBlockTimeSpanRequest? _$v;

  Date? _endDate;
  Date? get endDate => _$this._endDate;
  set endDate(Date? endDate) => _$this._endDate = endDate;

  Date? _startDate;
  Date? get startDate => _$this._startDate;
  set startDate(Date? startDate) => _$this._startDate = startDate;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateBlockTimeSpanRequestBuilder() {
    UpdateBlockTimeSpanRequest._defaults(this);
  }

  UpdateBlockTimeSpanRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endDate = $v.endDate;
      _startDate = $v.startDate;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateBlockTimeSpanRequest other) {
    _$v = other as _$UpdateBlockTimeSpanRequest;
  }

  @override
  void update(void Function(UpdateBlockTimeSpanRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateBlockTimeSpanRequest build() => _build();

  _$UpdateBlockTimeSpanRequest _build() {
    final _$result = _$v ??
        _$UpdateBlockTimeSpanRequest._(
          endDate: endDate,
          startDate: startDate,
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'UpdateBlockTimeSpanRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
