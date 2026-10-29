// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_job.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportJob extends AiImportJob {
  @override
  final BuiltList<AppliedEpisode>? appliedEpisodes;
  @override
  final BuiltList<AiImportAttempt>? attempts;
  @override
  final String? blockId;
  @override
  final CostBreakdown? cost;
  @override
  final DateTime createdAt;
  @override
  final String dedupKey;
  @override
  final String documentDigest;
  @override
  final DocumentKind documentKind;
  @override
  final String id;
  @override
  final String? lastError;
  @override
  final int maxRetries;
  @override
  final DateTime? nextAttemptAt;
  @override
  final String? previewHandle;
  @override
  final AiImportProgress? progress;
  @override
  final int retries;
  @override
  final String? sourceFileName;
  @override
  final SourceFormat sourceFormat;
  @override
  final String sourceHandle;
  @override
  final JobStatus status;
  @override
  final JobTelemetrySummary? telemetry;
  @override
  final DateTime updatedAt;
  @override
  final String userId;

  factory _$AiImportJob([void Function(AiImportJobBuilder)? updates]) =>
      (AiImportJobBuilder()..update(updates))._build();

  _$AiImportJob._(
      {this.appliedEpisodes,
      this.attempts,
      this.blockId,
      this.cost,
      required this.createdAt,
      required this.dedupKey,
      required this.documentDigest,
      required this.documentKind,
      required this.id,
      this.lastError,
      required this.maxRetries,
      this.nextAttemptAt,
      this.previewHandle,
      this.progress,
      required this.retries,
      this.sourceFileName,
      required this.sourceFormat,
      required this.sourceHandle,
      required this.status,
      this.telemetry,
      required this.updatedAt,
      required this.userId})
      : super._();
  @override
  AiImportJob rebuild(void Function(AiImportJobBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportJobBuilder toBuilder() => AiImportJobBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportJob &&
        appliedEpisodes == other.appliedEpisodes &&
        attempts == other.attempts &&
        blockId == other.blockId &&
        cost == other.cost &&
        createdAt == other.createdAt &&
        dedupKey == other.dedupKey &&
        documentDigest == other.documentDigest &&
        documentKind == other.documentKind &&
        id == other.id &&
        lastError == other.lastError &&
        maxRetries == other.maxRetries &&
        nextAttemptAt == other.nextAttemptAt &&
        previewHandle == other.previewHandle &&
        progress == other.progress &&
        retries == other.retries &&
        sourceFileName == other.sourceFileName &&
        sourceFormat == other.sourceFormat &&
        sourceHandle == other.sourceHandle &&
        status == other.status &&
        telemetry == other.telemetry &&
        updatedAt == other.updatedAt &&
        userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appliedEpisodes.hashCode);
    _$hash = $jc(_$hash, attempts.hashCode);
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jc(_$hash, cost.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, dedupKey.hashCode);
    _$hash = $jc(_$hash, documentDigest.hashCode);
    _$hash = $jc(_$hash, documentKind.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, lastError.hashCode);
    _$hash = $jc(_$hash, maxRetries.hashCode);
    _$hash = $jc(_$hash, nextAttemptAt.hashCode);
    _$hash = $jc(_$hash, previewHandle.hashCode);
    _$hash = $jc(_$hash, progress.hashCode);
    _$hash = $jc(_$hash, retries.hashCode);
    _$hash = $jc(_$hash, sourceFileName.hashCode);
    _$hash = $jc(_$hash, sourceFormat.hashCode);
    _$hash = $jc(_$hash, sourceHandle.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, telemetry.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportJob')
          ..add('appliedEpisodes', appliedEpisodes)
          ..add('attempts', attempts)
          ..add('blockId', blockId)
          ..add('cost', cost)
          ..add('createdAt', createdAt)
          ..add('dedupKey', dedupKey)
          ..add('documentDigest', documentDigest)
          ..add('documentKind', documentKind)
          ..add('id', id)
          ..add('lastError', lastError)
          ..add('maxRetries', maxRetries)
          ..add('nextAttemptAt', nextAttemptAt)
          ..add('previewHandle', previewHandle)
          ..add('progress', progress)
          ..add('retries', retries)
          ..add('sourceFileName', sourceFileName)
          ..add('sourceFormat', sourceFormat)
          ..add('sourceHandle', sourceHandle)
          ..add('status', status)
          ..add('telemetry', telemetry)
          ..add('updatedAt', updatedAt)
          ..add('userId', userId))
        .toString();
  }
}

class AiImportJobBuilder implements Builder<AiImportJob, AiImportJobBuilder> {
  _$AiImportJob? _$v;

  ListBuilder<AppliedEpisode>? _appliedEpisodes;
  ListBuilder<AppliedEpisode> get appliedEpisodes =>
      _$this._appliedEpisodes ??= ListBuilder<AppliedEpisode>();
  set appliedEpisodes(ListBuilder<AppliedEpisode>? appliedEpisodes) =>
      _$this._appliedEpisodes = appliedEpisodes;

  ListBuilder<AiImportAttempt>? _attempts;
  ListBuilder<AiImportAttempt> get attempts =>
      _$this._attempts ??= ListBuilder<AiImportAttempt>();
  set attempts(ListBuilder<AiImportAttempt>? attempts) =>
      _$this._attempts = attempts;

  String? _blockId;
  String? get blockId => _$this._blockId;
  set blockId(String? blockId) => _$this._blockId = blockId;

  CostBreakdownBuilder? _cost;
  CostBreakdownBuilder get cost => _$this._cost ??= CostBreakdownBuilder();
  set cost(CostBreakdownBuilder? cost) => _$this._cost = cost;

  DateTime? _createdAt;
  DateTime? get createdAt => _$this._createdAt;
  set createdAt(DateTime? createdAt) => _$this._createdAt = createdAt;

  String? _dedupKey;
  String? get dedupKey => _$this._dedupKey;
  set dedupKey(String? dedupKey) => _$this._dedupKey = dedupKey;

  String? _documentDigest;
  String? get documentDigest => _$this._documentDigest;
  set documentDigest(String? documentDigest) =>
      _$this._documentDigest = documentDigest;

  DocumentKind? _documentKind;
  DocumentKind? get documentKind => _$this._documentKind;
  set documentKind(DocumentKind? documentKind) =>
      _$this._documentKind = documentKind;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _lastError;
  String? get lastError => _$this._lastError;
  set lastError(String? lastError) => _$this._lastError = lastError;

  int? _maxRetries;
  int? get maxRetries => _$this._maxRetries;
  set maxRetries(int? maxRetries) => _$this._maxRetries = maxRetries;

  DateTime? _nextAttemptAt;
  DateTime? get nextAttemptAt => _$this._nextAttemptAt;
  set nextAttemptAt(DateTime? nextAttemptAt) =>
      _$this._nextAttemptAt = nextAttemptAt;

  String? _previewHandle;
  String? get previewHandle => _$this._previewHandle;
  set previewHandle(String? previewHandle) =>
      _$this._previewHandle = previewHandle;

  AiImportProgressBuilder? _progress;
  AiImportProgressBuilder get progress =>
      _$this._progress ??= AiImportProgressBuilder();
  set progress(AiImportProgressBuilder? progress) =>
      _$this._progress = progress;

  int? _retries;
  int? get retries => _$this._retries;
  set retries(int? retries) => _$this._retries = retries;

  String? _sourceFileName;
  String? get sourceFileName => _$this._sourceFileName;
  set sourceFileName(String? sourceFileName) =>
      _$this._sourceFileName = sourceFileName;

  SourceFormat? _sourceFormat;
  SourceFormat? get sourceFormat => _$this._sourceFormat;
  set sourceFormat(SourceFormat? sourceFormat) =>
      _$this._sourceFormat = sourceFormat;

  String? _sourceHandle;
  String? get sourceHandle => _$this._sourceHandle;
  set sourceHandle(String? sourceHandle) => _$this._sourceHandle = sourceHandle;

  JobStatus? _status;
  JobStatus? get status => _$this._status;
  set status(JobStatus? status) => _$this._status = status;

  JobTelemetrySummaryBuilder? _telemetry;
  JobTelemetrySummaryBuilder get telemetry =>
      _$this._telemetry ??= JobTelemetrySummaryBuilder();
  set telemetry(JobTelemetrySummaryBuilder? telemetry) =>
      _$this._telemetry = telemetry;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  String? _userId;
  String? get userId => _$this._userId;
  set userId(String? userId) => _$this._userId = userId;

  AiImportJobBuilder() {
    AiImportJob._defaults(this);
  }

  AiImportJobBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appliedEpisodes = $v.appliedEpisodes?.toBuilder();
      _attempts = $v.attempts?.toBuilder();
      _blockId = $v.blockId;
      _cost = $v.cost?.toBuilder();
      _createdAt = $v.createdAt;
      _dedupKey = $v.dedupKey;
      _documentDigest = $v.documentDigest;
      _documentKind = $v.documentKind;
      _id = $v.id;
      _lastError = $v.lastError;
      _maxRetries = $v.maxRetries;
      _nextAttemptAt = $v.nextAttemptAt;
      _previewHandle = $v.previewHandle;
      _progress = $v.progress?.toBuilder();
      _retries = $v.retries;
      _sourceFileName = $v.sourceFileName;
      _sourceFormat = $v.sourceFormat;
      _sourceHandle = $v.sourceHandle;
      _status = $v.status;
      _telemetry = $v.telemetry?.toBuilder();
      _updatedAt = $v.updatedAt;
      _userId = $v.userId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportJob other) {
    _$v = other as _$AiImportJob;
  }

  @override
  void update(void Function(AiImportJobBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportJob build() => _build();

  _$AiImportJob _build() {
    _$AiImportJob _$result;
    try {
      _$result = _$v ??
          _$AiImportJob._(
            appliedEpisodes: _appliedEpisodes?.build(),
            attempts: _attempts?.build(),
            blockId: blockId,
            cost: _cost?.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
                createdAt, r'AiImportJob', 'createdAt'),
            dedupKey: BuiltValueNullFieldError.checkNotNull(
                dedupKey, r'AiImportJob', 'dedupKey'),
            documentDigest: BuiltValueNullFieldError.checkNotNull(
                documentDigest, r'AiImportJob', 'documentDigest'),
            documentKind: BuiltValueNullFieldError.checkNotNull(
                documentKind, r'AiImportJob', 'documentKind'),
            id: BuiltValueNullFieldError.checkNotNull(id, r'AiImportJob', 'id'),
            lastError: lastError,
            maxRetries: BuiltValueNullFieldError.checkNotNull(
                maxRetries, r'AiImportJob', 'maxRetries'),
            nextAttemptAt: nextAttemptAt,
            previewHandle: previewHandle,
            progress: _progress?.build(),
            retries: BuiltValueNullFieldError.checkNotNull(
                retries, r'AiImportJob', 'retries'),
            sourceFileName: sourceFileName,
            sourceFormat: BuiltValueNullFieldError.checkNotNull(
                sourceFormat, r'AiImportJob', 'sourceFormat'),
            sourceHandle: BuiltValueNullFieldError.checkNotNull(
                sourceHandle, r'AiImportJob', 'sourceHandle'),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'AiImportJob', 'status'),
            telemetry: _telemetry?.build(),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'AiImportJob', 'updatedAt'),
            userId: BuiltValueNullFieldError.checkNotNull(
                userId, r'AiImportJob', 'userId'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'appliedEpisodes';
        _appliedEpisodes?.build();
        _$failedField = 'attempts';
        _attempts?.build();

        _$failedField = 'cost';
        _cost?.build();

        _$failedField = 'progress';
        _progress?.build();

        _$failedField = 'telemetry';
        _telemetry?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiImportJob', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
