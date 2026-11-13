// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_job.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportJob extends AiImportJob {
  @override
  final bool? applied;
  @override
  final BuiltList<AppliedEpisode>? appliedEpisodes;
  @override
  final ApplyProgress? applyProgress;
  @override
  final ApplyRunOutcome? applyResult;
  @override
  final String? applyRunId;
  @override
  final ApplyState? applyState;
  @override
  final BuiltList<AiImportAttempt>? attempts;
  @override
  final String? blockId;
  @override
  final CostBreakdown? cost;
  @override
  final DateTime createdAt;
  @override
  final DecisionTelemetry? decisionTelemetry;
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
  final String? model;
  @override
  final DateTime? nextAttemptAt;
  @override
  final String? previewHandle;
  @override
  final AiImportProgress? progress;
  @override
  final LlmProvider? provider;
  @override
  final ProviderHold? providerHold;
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
  final AiImportTarget? target;
  @override
  final JobTelemetrySummary? telemetry;
  @override
  final DateTime updatedAt;
  @override
  final String userId;

  factory _$AiImportJob([void Function(AiImportJobBuilder)? updates]) =>
      (AiImportJobBuilder()..update(updates))._build();

  _$AiImportJob._(
      {this.applied,
      this.appliedEpisodes,
      this.applyProgress,
      this.applyResult,
      this.applyRunId,
      this.applyState,
      this.attempts,
      this.blockId,
      this.cost,
      required this.createdAt,
      this.decisionTelemetry,
      required this.dedupKey,
      required this.documentDigest,
      required this.documentKind,
      required this.id,
      this.lastError,
      required this.maxRetries,
      this.model,
      this.nextAttemptAt,
      this.previewHandle,
      this.progress,
      this.provider,
      this.providerHold,
      required this.retries,
      this.sourceFileName,
      required this.sourceFormat,
      required this.sourceHandle,
      required this.status,
      this.target,
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
        applied == other.applied &&
        appliedEpisodes == other.appliedEpisodes &&
        applyProgress == other.applyProgress &&
        applyResult == other.applyResult &&
        applyRunId == other.applyRunId &&
        applyState == other.applyState &&
        attempts == other.attempts &&
        blockId == other.blockId &&
        cost == other.cost &&
        createdAt == other.createdAt &&
        decisionTelemetry == other.decisionTelemetry &&
        dedupKey == other.dedupKey &&
        documentDigest == other.documentDigest &&
        documentKind == other.documentKind &&
        id == other.id &&
        lastError == other.lastError &&
        maxRetries == other.maxRetries &&
        model == other.model &&
        nextAttemptAt == other.nextAttemptAt &&
        previewHandle == other.previewHandle &&
        progress == other.progress &&
        provider == other.provider &&
        providerHold == other.providerHold &&
        retries == other.retries &&
        sourceFileName == other.sourceFileName &&
        sourceFormat == other.sourceFormat &&
        sourceHandle == other.sourceHandle &&
        status == other.status &&
        target == other.target &&
        telemetry == other.telemetry &&
        updatedAt == other.updatedAt &&
        userId == other.userId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, applied.hashCode);
    _$hash = $jc(_$hash, appliedEpisodes.hashCode);
    _$hash = $jc(_$hash, applyProgress.hashCode);
    _$hash = $jc(_$hash, applyResult.hashCode);
    _$hash = $jc(_$hash, applyRunId.hashCode);
    _$hash = $jc(_$hash, applyState.hashCode);
    _$hash = $jc(_$hash, attempts.hashCode);
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jc(_$hash, cost.hashCode);
    _$hash = $jc(_$hash, createdAt.hashCode);
    _$hash = $jc(_$hash, decisionTelemetry.hashCode);
    _$hash = $jc(_$hash, dedupKey.hashCode);
    _$hash = $jc(_$hash, documentDigest.hashCode);
    _$hash = $jc(_$hash, documentKind.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, lastError.hashCode);
    _$hash = $jc(_$hash, maxRetries.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, nextAttemptAt.hashCode);
    _$hash = $jc(_$hash, previewHandle.hashCode);
    _$hash = $jc(_$hash, progress.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, providerHold.hashCode);
    _$hash = $jc(_$hash, retries.hashCode);
    _$hash = $jc(_$hash, sourceFileName.hashCode);
    _$hash = $jc(_$hash, sourceFormat.hashCode);
    _$hash = $jc(_$hash, sourceHandle.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, target.hashCode);
    _$hash = $jc(_$hash, telemetry.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, userId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportJob')
          ..add('applied', applied)
          ..add('appliedEpisodes', appliedEpisodes)
          ..add('applyProgress', applyProgress)
          ..add('applyResult', applyResult)
          ..add('applyRunId', applyRunId)
          ..add('applyState', applyState)
          ..add('attempts', attempts)
          ..add('blockId', blockId)
          ..add('cost', cost)
          ..add('createdAt', createdAt)
          ..add('decisionTelemetry', decisionTelemetry)
          ..add('dedupKey', dedupKey)
          ..add('documentDigest', documentDigest)
          ..add('documentKind', documentKind)
          ..add('id', id)
          ..add('lastError', lastError)
          ..add('maxRetries', maxRetries)
          ..add('model', model)
          ..add('nextAttemptAt', nextAttemptAt)
          ..add('previewHandle', previewHandle)
          ..add('progress', progress)
          ..add('provider', provider)
          ..add('providerHold', providerHold)
          ..add('retries', retries)
          ..add('sourceFileName', sourceFileName)
          ..add('sourceFormat', sourceFormat)
          ..add('sourceHandle', sourceHandle)
          ..add('status', status)
          ..add('target', target)
          ..add('telemetry', telemetry)
          ..add('updatedAt', updatedAt)
          ..add('userId', userId))
        .toString();
  }
}

class AiImportJobBuilder implements Builder<AiImportJob, AiImportJobBuilder> {
  _$AiImportJob? _$v;

  bool? _applied;
  bool? get applied => _$this._applied;
  set applied(bool? applied) => _$this._applied = applied;

  ListBuilder<AppliedEpisode>? _appliedEpisodes;
  ListBuilder<AppliedEpisode> get appliedEpisodes =>
      _$this._appliedEpisodes ??= ListBuilder<AppliedEpisode>();
  set appliedEpisodes(ListBuilder<AppliedEpisode>? appliedEpisodes) =>
      _$this._appliedEpisodes = appliedEpisodes;

  ApplyProgressBuilder? _applyProgress;
  ApplyProgressBuilder get applyProgress =>
      _$this._applyProgress ??= ApplyProgressBuilder();
  set applyProgress(ApplyProgressBuilder? applyProgress) =>
      _$this._applyProgress = applyProgress;

  ApplyRunOutcomeBuilder? _applyResult;
  ApplyRunOutcomeBuilder get applyResult =>
      _$this._applyResult ??= ApplyRunOutcomeBuilder();
  set applyResult(ApplyRunOutcomeBuilder? applyResult) =>
      _$this._applyResult = applyResult;

  String? _applyRunId;
  String? get applyRunId => _$this._applyRunId;
  set applyRunId(String? applyRunId) => _$this._applyRunId = applyRunId;

  ApplyState? _applyState;
  ApplyState? get applyState => _$this._applyState;
  set applyState(ApplyState? applyState) => _$this._applyState = applyState;

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

  DecisionTelemetryBuilder? _decisionTelemetry;
  DecisionTelemetryBuilder get decisionTelemetry =>
      _$this._decisionTelemetry ??= DecisionTelemetryBuilder();
  set decisionTelemetry(DecisionTelemetryBuilder? decisionTelemetry) =>
      _$this._decisionTelemetry = decisionTelemetry;

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

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

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

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  ProviderHoldBuilder? _providerHold;
  ProviderHoldBuilder get providerHold =>
      _$this._providerHold ??= ProviderHoldBuilder();
  set providerHold(ProviderHoldBuilder? providerHold) =>
      _$this._providerHold = providerHold;

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

  AiImportTargetBuilder? _target;
  AiImportTargetBuilder get target =>
      _$this._target ??= AiImportTargetBuilder();
  set target(AiImportTargetBuilder? target) => _$this._target = target;

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
      _applied = $v.applied;
      _appliedEpisodes = $v.appliedEpisodes?.toBuilder();
      _applyProgress = $v.applyProgress?.toBuilder();
      _applyResult = $v.applyResult?.toBuilder();
      _applyRunId = $v.applyRunId;
      _applyState = $v.applyState;
      _attempts = $v.attempts?.toBuilder();
      _blockId = $v.blockId;
      _cost = $v.cost?.toBuilder();
      _createdAt = $v.createdAt;
      _decisionTelemetry = $v.decisionTelemetry?.toBuilder();
      _dedupKey = $v.dedupKey;
      _documentDigest = $v.documentDigest;
      _documentKind = $v.documentKind;
      _id = $v.id;
      _lastError = $v.lastError;
      _maxRetries = $v.maxRetries;
      _model = $v.model;
      _nextAttemptAt = $v.nextAttemptAt;
      _previewHandle = $v.previewHandle;
      _progress = $v.progress?.toBuilder();
      _provider = $v.provider;
      _providerHold = $v.providerHold?.toBuilder();
      _retries = $v.retries;
      _sourceFileName = $v.sourceFileName;
      _sourceFormat = $v.sourceFormat;
      _sourceHandle = $v.sourceHandle;
      _status = $v.status;
      _target = $v.target?.toBuilder();
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
            applied: applied,
            appliedEpisodes: _appliedEpisodes?.build(),
            applyProgress: _applyProgress?.build(),
            applyResult: _applyResult?.build(),
            applyRunId: applyRunId,
            applyState: applyState,
            attempts: _attempts?.build(),
            blockId: blockId,
            cost: _cost?.build(),
            createdAt: BuiltValueNullFieldError.checkNotNull(
                createdAt, r'AiImportJob', 'createdAt'),
            decisionTelemetry: _decisionTelemetry?.build(),
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
            model: model,
            nextAttemptAt: nextAttemptAt,
            previewHandle: previewHandle,
            progress: _progress?.build(),
            provider: provider,
            providerHold: _providerHold?.build(),
            retries: BuiltValueNullFieldError.checkNotNull(
                retries, r'AiImportJob', 'retries'),
            sourceFileName: sourceFileName,
            sourceFormat: BuiltValueNullFieldError.checkNotNull(
                sourceFormat, r'AiImportJob', 'sourceFormat'),
            sourceHandle: BuiltValueNullFieldError.checkNotNull(
                sourceHandle, r'AiImportJob', 'sourceHandle'),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'AiImportJob', 'status'),
            target: _target?.build(),
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
        _$failedField = 'applyProgress';
        _applyProgress?.build();
        _$failedField = 'applyResult';
        _applyResult?.build();

        _$failedField = 'attempts';
        _attempts?.build();

        _$failedField = 'cost';
        _cost?.build();

        _$failedField = 'decisionTelemetry';
        _decisionTelemetry?.build();

        _$failedField = 'progress';
        _progress?.build();

        _$failedField = 'providerHold';
        _providerHold?.build();

        _$failedField = 'target';
        _target?.build();
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
