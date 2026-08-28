// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_season_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateSeasonRequest extends CreateSeasonRequest {
  @override
  final int number;
  @override
  final String seriesId;
  @override
  final String? title;

  factory _$CreateSeasonRequest(
          [void Function(CreateSeasonRequestBuilder)? updates]) =>
      (CreateSeasonRequestBuilder()..update(updates))._build();

  _$CreateSeasonRequest._(
      {required this.number, required this.seriesId, this.title})
      : super._();
  @override
  CreateSeasonRequest rebuild(
          void Function(CreateSeasonRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateSeasonRequestBuilder toBuilder() =>
      CreateSeasonRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateSeasonRequest &&
        number == other.number &&
        seriesId == other.seriesId &&
        title == other.title;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, seriesId.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateSeasonRequest')
          ..add('number', number)
          ..add('seriesId', seriesId)
          ..add('title', title))
        .toString();
  }
}

class CreateSeasonRequestBuilder
    implements Builder<CreateSeasonRequest, CreateSeasonRequestBuilder> {
  _$CreateSeasonRequest? _$v;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  String? _seriesId;
  String? get seriesId => _$this._seriesId;
  set seriesId(String? seriesId) => _$this._seriesId = seriesId;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  CreateSeasonRequestBuilder() {
    CreateSeasonRequest._defaults(this);
  }

  CreateSeasonRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _number = $v.number;
      _seriesId = $v.seriesId;
      _title = $v.title;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateSeasonRequest other) {
    _$v = other as _$CreateSeasonRequest;
  }

  @override
  void update(void Function(CreateSeasonRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateSeasonRequest build() => _build();

  _$CreateSeasonRequest _build() {
    final _$result = _$v ??
        _$CreateSeasonRequest._(
          number: BuiltValueNullFieldError.checkNotNull(
              number, r'CreateSeasonRequest', 'number'),
          seriesId: BuiltValueNullFieldError.checkNotNull(
              seriesId, r'CreateSeasonRequest', 'seriesId'),
          title: title,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
