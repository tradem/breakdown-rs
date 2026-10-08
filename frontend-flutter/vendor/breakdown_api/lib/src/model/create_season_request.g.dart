// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_season_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateSeasonRequest extends CreateSeasonRequest {
  @override
  final int number;
  @override
  final String projectId;
  @override
  final String? title;

  factory _$CreateSeasonRequest(
          [void Function(CreateSeasonRequestBuilder)? updates]) =>
      (CreateSeasonRequestBuilder()..update(updates))._build();

  _$CreateSeasonRequest._(
      {required this.number, required this.projectId, this.title})
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
        projectId == other.projectId &&
        title == other.title;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, projectId.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateSeasonRequest')
          ..add('number', number)
          ..add('projectId', projectId)
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

  String? _projectId;
  String? get projectId => _$this._projectId;
  set projectId(String? projectId) => _$this._projectId = projectId;

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
      _projectId = $v.projectId;
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
          projectId: BuiltValueNullFieldError.checkNotNull(
              projectId, r'CreateSeasonRequest', 'projectId'),
          title: title,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
