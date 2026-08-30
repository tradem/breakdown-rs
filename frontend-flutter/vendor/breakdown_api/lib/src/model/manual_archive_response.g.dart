// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manual_archive_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ManualArchiveResponse extends ManualArchiveResponse {
  @override
  final BuiltList<ManualArchiveJobResult> jobs;

  factory _$ManualArchiveResponse(
          [void Function(ManualArchiveResponseBuilder)? updates]) =>
      (ManualArchiveResponseBuilder()..update(updates))._build();

  _$ManualArchiveResponse._({required this.jobs}) : super._();
  @override
  ManualArchiveResponse rebuild(
          void Function(ManualArchiveResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ManualArchiveResponseBuilder toBuilder() =>
      ManualArchiveResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ManualArchiveResponse && jobs == other.jobs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, jobs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ManualArchiveResponse')
          ..add('jobs', jobs))
        .toString();
  }
}

class ManualArchiveResponseBuilder
    implements Builder<ManualArchiveResponse, ManualArchiveResponseBuilder> {
  _$ManualArchiveResponse? _$v;

  ListBuilder<ManualArchiveJobResult>? _jobs;
  ListBuilder<ManualArchiveJobResult> get jobs =>
      _$this._jobs ??= ListBuilder<ManualArchiveJobResult>();
  set jobs(ListBuilder<ManualArchiveJobResult>? jobs) => _$this._jobs = jobs;

  ManualArchiveResponseBuilder() {
    ManualArchiveResponse._defaults(this);
  }

  ManualArchiveResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _jobs = $v.jobs.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ManualArchiveResponse other) {
    _$v = other as _$ManualArchiveResponse;
  }

  @override
  void update(void Function(ManualArchiveResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ManualArchiveResponse build() => _build();

  _$ManualArchiveResponse _build() {
    _$ManualArchiveResponse _$result;
    try {
      _$result = _$v ??
          _$ManualArchiveResponse._(
            jobs: jobs.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'jobs';
        jobs.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ManualArchiveResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
