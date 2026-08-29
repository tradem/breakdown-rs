// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'problem_details.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ProblemDetails extends ProblemDetails {
  @override
  final String code;
  @override
  final String detail;
  @override
  final BuiltMap<String, JsonObject?>? extensions;
  @override
  final int status;
  @override
  final String title;
  @override
  final String traceId;
  @override
  final String type;

  factory _$ProblemDetails([void Function(ProblemDetailsBuilder)? updates]) =>
      (ProblemDetailsBuilder()..update(updates))._build();

  _$ProblemDetails._(
      {required this.code,
      required this.detail,
      this.extensions,
      required this.status,
      required this.title,
      required this.traceId,
      required this.type})
      : super._();
  @override
  ProblemDetails rebuild(void Function(ProblemDetailsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ProblemDetailsBuilder toBuilder() => ProblemDetailsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ProblemDetails &&
        code == other.code &&
        detail == other.detail &&
        extensions == other.extensions &&
        status == other.status &&
        title == other.title &&
        traceId == other.traceId &&
        type == other.type;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, detail.hashCode);
    _$hash = $jc(_$hash, extensions.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, traceId.hashCode);
    _$hash = $jc(_$hash, type.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ProblemDetails')
          ..add('code', code)
          ..add('detail', detail)
          ..add('extensions', extensions)
          ..add('status', status)
          ..add('title', title)
          ..add('traceId', traceId)
          ..add('type', type))
        .toString();
  }
}

class ProblemDetailsBuilder
    implements Builder<ProblemDetails, ProblemDetailsBuilder> {
  _$ProblemDetails? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  String? _detail;
  String? get detail => _$this._detail;
  set detail(String? detail) => _$this._detail = detail;

  MapBuilder<String, JsonObject?>? _extensions;
  MapBuilder<String, JsonObject?> get extensions =>
      _$this._extensions ??= MapBuilder<String, JsonObject?>();
  set extensions(MapBuilder<String, JsonObject?>? extensions) =>
      _$this._extensions = extensions;

  int? _status;
  int? get status => _$this._status;
  set status(int? status) => _$this._status = status;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  String? _traceId;
  String? get traceId => _$this._traceId;
  set traceId(String? traceId) => _$this._traceId = traceId;

  String? _type;
  String? get type => _$this._type;
  set type(String? type) => _$this._type = type;

  ProblemDetailsBuilder() {
    ProblemDetails._defaults(this);
  }

  ProblemDetailsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _detail = $v.detail;
      _extensions = $v.extensions?.toBuilder();
      _status = $v.status;
      _title = $v.title;
      _traceId = $v.traceId;
      _type = $v.type;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ProblemDetails other) {
    _$v = other as _$ProblemDetails;
  }

  @override
  void update(void Function(ProblemDetailsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ProblemDetails build() => _build();

  _$ProblemDetails _build() {
    _$ProblemDetails _$result;
    try {
      _$result = _$v ??
          _$ProblemDetails._(
            code: BuiltValueNullFieldError.checkNotNull(
                code, r'ProblemDetails', 'code'),
            detail: BuiltValueNullFieldError.checkNotNull(
                detail, r'ProblemDetails', 'detail'),
            extensions: _extensions?.build(),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'ProblemDetails', 'status'),
            title: BuiltValueNullFieldError.checkNotNull(
                title, r'ProblemDetails', 'title'),
            traceId: BuiltValueNullFieldError.checkNotNull(
                traceId, r'ProblemDetails', 'traceId'),
            type: BuiltValueNullFieldError.checkNotNull(
                type, r'ProblemDetails', 'type'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'extensions';
        _extensions?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ProblemDetails', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
