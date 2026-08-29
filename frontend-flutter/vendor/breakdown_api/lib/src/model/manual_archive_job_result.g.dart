// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manual_archive_job_result.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ManualArchiveJobResult extends ManualArchiveJobResult {
  @override
  final bool alreadyEnqueued;
  @override
  final String jobId;
  @override
  final String kind;
  @override
  final String status;

  factory _$ManualArchiveJobResult(
          [void Function(ManualArchiveJobResultBuilder)? updates]) =>
      (ManualArchiveJobResultBuilder()..update(updates))._build();

  _$ManualArchiveJobResult._(
      {required this.alreadyEnqueued,
      required this.jobId,
      required this.kind,
      required this.status})
      : super._();
  @override
  ManualArchiveJobResult rebuild(
          void Function(ManualArchiveJobResultBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ManualArchiveJobResultBuilder toBuilder() =>
      ManualArchiveJobResultBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ManualArchiveJobResult &&
        alreadyEnqueued == other.alreadyEnqueued &&
        jobId == other.jobId &&
        kind == other.kind &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, alreadyEnqueued.hashCode);
    _$hash = $jc(_$hash, jobId.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ManualArchiveJobResult')
          ..add('alreadyEnqueued', alreadyEnqueued)
          ..add('jobId', jobId)
          ..add('kind', kind)
          ..add('status', status))
        .toString();
  }
}

class ManualArchiveJobResultBuilder
    implements Builder<ManualArchiveJobResult, ManualArchiveJobResultBuilder> {
  _$ManualArchiveJobResult? _$v;

  bool? _alreadyEnqueued;
  bool? get alreadyEnqueued => _$this._alreadyEnqueued;
  set alreadyEnqueued(bool? alreadyEnqueued) =>
      _$this._alreadyEnqueued = alreadyEnqueued;

  String? _jobId;
  String? get jobId => _$this._jobId;
  set jobId(String? jobId) => _$this._jobId = jobId;

  String? _kind;
  String? get kind => _$this._kind;
  set kind(String? kind) => _$this._kind = kind;

  String? _status;
  String? get status => _$this._status;
  set status(String? status) => _$this._status = status;

  ManualArchiveJobResultBuilder() {
    ManualArchiveJobResult._defaults(this);
  }

  ManualArchiveJobResultBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _alreadyEnqueued = $v.alreadyEnqueued;
      _jobId = $v.jobId;
      _kind = $v.kind;
      _status = $v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ManualArchiveJobResult other) {
    _$v = other as _$ManualArchiveJobResult;
  }

  @override
  void update(void Function(ManualArchiveJobResultBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ManualArchiveJobResult build() => _build();

  _$ManualArchiveJobResult _build() {
    final _$result = _$v ??
        _$ManualArchiveJobResult._(
          alreadyEnqueued: BuiltValueNullFieldError.checkNotNull(
              alreadyEnqueued, r'ManualArchiveJobResult', 'alreadyEnqueued'),
          jobId: BuiltValueNullFieldError.checkNotNull(
              jobId, r'ManualArchiveJobResult', 'jobId'),
          kind: BuiltValueNullFieldError.checkNotNull(
              kind, r'ManualArchiveJobResult', 'kind'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'ManualArchiveJobResult', 'status'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
