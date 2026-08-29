// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_job_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportJobResponse extends AiImportJobResponse {
  @override
  final AiImportJob job;

  factory _$AiImportJobResponse(
          [void Function(AiImportJobResponseBuilder)? updates]) =>
      (AiImportJobResponseBuilder()..update(updates))._build();

  _$AiImportJobResponse._({required this.job}) : super._();
  @override
  AiImportJobResponse rebuild(
          void Function(AiImportJobResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportJobResponseBuilder toBuilder() =>
      AiImportJobResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportJobResponse && job == other.job;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, job.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportJobResponse')
          ..add('job', job))
        .toString();
  }
}

class AiImportJobResponseBuilder
    implements Builder<AiImportJobResponse, AiImportJobResponseBuilder> {
  _$AiImportJobResponse? _$v;

  AiImportJobBuilder? _job;
  AiImportJobBuilder get job => _$this._job ??= AiImportJobBuilder();
  set job(AiImportJobBuilder? job) => _$this._job = job;

  AiImportJobResponseBuilder() {
    AiImportJobResponse._defaults(this);
  }

  AiImportJobResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _job = $v.job.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportJobResponse other) {
    _$v = other as _$AiImportJobResponse;
  }

  @override
  void update(void Function(AiImportJobResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportJobResponse build() => _build();

  _$AiImportJobResponse _build() {
    _$AiImportJobResponse _$result;
    try {
      _$result = _$v ??
          _$AiImportJobResponse._(
            job: job.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'job';
        job.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiImportJobResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
