// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_attempt.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportAttempt extends AiImportAttempt {
  @override
  final int attemptNo;
  @override
  final DateTime createdAt;
  @override
  final String? errorSummary;
  @override
  final bool retryable;
  @override
  final JobStatus status;

  factory _$AiImportAttempt([void Function(AiImportAttemptBuilder)? updates]) =>
      (AiImportAttemptBuilder()..update(updates))._build();

  _$AiImportAttempt._(
      {required this.attemptNo,
      required this.createdAt,
      this.errorSummary,
      required this.retryable,
      required this.status})
      : super._();
  @override
  AiImportAttempt rebuild(void Function(AiImportAttemptBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportAttemptBuilder toBuilder() => AiImportAttemptBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportAttempt &&
        attemptNo == other.attemptNo &&
        createdAt == other.createdAt &&
        errorSummary == other.errorSummary &&
        retryable == other.retryable &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, attemptNo.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, errorSummary.hashCode);
    _$hash = $jc(_$hash, retryable.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportAttempt')
          ..add('attemptNo', attemptNo)
          ..add('createdAt', createdAt)
          ..add('errorSummary', errorSummary)
          ..add('retryable', retryable)
          ..add('status', status))
        .toString();
  }
}

class AiImportAttemptBuilder
    implements Builder<AiImportAttempt, AiImportAttemptBuilder> {
  _$AiImportAttempt? _$v;

  int? _attemptNo;
  int? get attemptNo => _$this._attemptNo;
  set attemptNo(int? attemptNo) => _$this._attemptNo = attemptNo;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _errorSummary;
  String? get errorSummary => _$this._errorSummary;
  set errorSummary(String? errorSummary) => _$this._errorSummary = errorSummary;

  bool? _retryable;
  bool? get retryable => _$this._retryable;
  set retryable(bool? retryable) => _$this._retryable = retryable;

  JobStatus? _status;
  JobStatus? get status => _$this._status;
  set status(JobStatus? status) => _$this._status = status;

  AiImportAttemptBuilder() {
    AiImportAttempt._defaults(this);
  }

  AiImportAttemptBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _attemptNo = $v.attemptNo;
      _createdAt = $v.createdAt;
      _errorSummary = $v.errorSummary;
      _retryable = $v.retryable;
      _status = $v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportAttempt other) {
    _$v = other as _$AiImportAttempt;
  }

  @override
  void update(void Function(AiImportAttemptBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportAttempt build() => _build();

  _$AiImportAttempt _build() {
    final _$result = _$v ??
        _$AiImportAttempt._(
          attemptNo: BuiltValueNullFieldError.checkNotNull(
              attemptNo, r'AiImportAttempt', 'attemptNo'),
          createdAt: BuiltValueNullFieldError.checkNotNull(
              createdAt, r'AiImportAttempt', 'createdAt'),
          errorSummary: errorSummary,
          retryable: BuiltValueNullFieldError.checkNotNull(
              retryable, r'AiImportAttempt', 'retryable'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'AiImportAttempt', 'status'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
