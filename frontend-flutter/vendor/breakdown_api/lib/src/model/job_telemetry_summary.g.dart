// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_telemetry_summary.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$JobTelemetrySummary extends JobTelemetrySummary {
  @override
  final int cachedTokensIn;
  @override
  final int chunkCount;
  @override
  final DocumentKind? docKind;
  @override
  final int energyMillijoules;
  @override
  final int latencyTotalMs;
  @override
  final String? model;
  @override
  final LlmProvider? provider;
  @override
  final int? scenesDetected;
  @override
  final int? scenesExtracted;
  @override
  final int? scenesSynthesized;
  @override
  final int tokensIn;
  @override
  final int tokensOut;

  factory _$JobTelemetrySummary(
          [void Function(JobTelemetrySummaryBuilder)? updates]) =>
      (JobTelemetrySummaryBuilder()..update(updates))._build();

  _$JobTelemetrySummary._(
      {required this.cachedTokensIn,
      required this.chunkCount,
      this.docKind,
      required this.energyMillijoules,
      required this.latencyTotalMs,
      this.model,
      this.provider,
      this.scenesDetected,
      this.scenesExtracted,
      this.scenesSynthesized,
      required this.tokensIn,
      required this.tokensOut})
      : super._();
  @override
  JobTelemetrySummary rebuild(
          void Function(JobTelemetrySummaryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  JobTelemetrySummaryBuilder toBuilder() =>
      JobTelemetrySummaryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is JobTelemetrySummary &&
        cachedTokensIn == other.cachedTokensIn &&
        chunkCount == other.chunkCount &&
        docKind == other.docKind &&
        energyMillijoules == other.energyMillijoules &&
        latencyTotalMs == other.latencyTotalMs &&
        model == other.model &&
        provider == other.provider &&
        scenesDetected == other.scenesDetected &&
        scenesExtracted == other.scenesExtracted &&
        scenesSynthesized == other.scenesSynthesized &&
        tokensIn == other.tokensIn &&
        tokensOut == other.tokensOut;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, cachedTokensIn.hashCode);
    _$hash = $jc(_$hash, chunkCount.hashCode);
    _$hash = $jc(_$hash, docKind.hashCode);
    _$hash = $jc(_$hash, energyMillijoules.hashCode);
    _$hash = $jc(_$hash, latencyTotalMs.hashCode);
    _$hash = $jc(_$hash, model.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, scenesDetected.hashCode);
    _$hash = $jc(_$hash, scenesExtracted.hashCode);
    _$hash = $jc(_$hash, scenesSynthesized.hashCode);
    _$hash = $jc(_$hash, tokensIn.hashCode);
    _$hash = $jc(_$hash, tokensOut.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'JobTelemetrySummary')
          ..add('cachedTokensIn', cachedTokensIn)
          ..add('chunkCount', chunkCount)
          ..add('docKind', docKind)
          ..add('energyMillijoules', energyMillijoules)
          ..add('latencyTotalMs', latencyTotalMs)
          ..add('model', model)
          ..add('provider', provider)
          ..add('scenesDetected', scenesDetected)
          ..add('scenesExtracted', scenesExtracted)
          ..add('scenesSynthesized', scenesSynthesized)
          ..add('tokensIn', tokensIn)
          ..add('tokensOut', tokensOut))
        .toString();
  }
}

class JobTelemetrySummaryBuilder
    implements Builder<JobTelemetrySummary, JobTelemetrySummaryBuilder> {
  _$JobTelemetrySummary? _$v;

  int? _cachedTokensIn;
  int? get cachedTokensIn => _$this._cachedTokensIn;
  set cachedTokensIn(int? cachedTokensIn) =>
      _$this._cachedTokensIn = cachedTokensIn;

  int? _chunkCount;
  int? get chunkCount => _$this._chunkCount;
  set chunkCount(int? chunkCount) => _$this._chunkCount = chunkCount;

  DocumentKind? _docKind;
  DocumentKind? get docKind => _$this._docKind;
  set docKind(DocumentKind? docKind) => _$this._docKind = docKind;

  int? _energyMillijoules;
  int? get energyMillijoules => _$this._energyMillijoules;
  set energyMillijoules(int? energyMillijoules) =>
      _$this._energyMillijoules = energyMillijoules;

  int? _latencyTotalMs;
  int? get latencyTotalMs => _$this._latencyTotalMs;
  set latencyTotalMs(int? latencyTotalMs) =>
      _$this._latencyTotalMs = latencyTotalMs;

  String? _model;
  String? get model => _$this._model;
  set model(String? model) => _$this._model = model;

  LlmProvider? _provider;
  LlmProvider? get provider => _$this._provider;
  set provider(LlmProvider? provider) => _$this._provider = provider;

  int? _scenesDetected;
  int? get scenesDetected => _$this._scenesDetected;
  set scenesDetected(int? scenesDetected) =>
      _$this._scenesDetected = scenesDetected;

  int? _scenesExtracted;
  int? get scenesExtracted => _$this._scenesExtracted;
  set scenesExtracted(int? scenesExtracted) =>
      _$this._scenesExtracted = scenesExtracted;

  int? _scenesSynthesized;
  int? get scenesSynthesized => _$this._scenesSynthesized;
  set scenesSynthesized(int? scenesSynthesized) =>
      _$this._scenesSynthesized = scenesSynthesized;

  int? _tokensIn;
  int? get tokensIn => _$this._tokensIn;
  set tokensIn(int? tokensIn) => _$this._tokensIn = tokensIn;

  int? _tokensOut;
  int? get tokensOut => _$this._tokensOut;
  set tokensOut(int? tokensOut) => _$this._tokensOut = tokensOut;

  JobTelemetrySummaryBuilder() {
    JobTelemetrySummary._defaults(this);
  }

  JobTelemetrySummaryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _cachedTokensIn = $v.cachedTokensIn;
      _chunkCount = $v.chunkCount;
      _docKind = $v.docKind;
      _energyMillijoules = $v.energyMillijoules;
      _latencyTotalMs = $v.latencyTotalMs;
      _model = $v.model;
      _provider = $v.provider;
      _scenesDetected = $v.scenesDetected;
      _scenesExtracted = $v.scenesExtracted;
      _scenesSynthesized = $v.scenesSynthesized;
      _tokensIn = $v.tokensIn;
      _tokensOut = $v.tokensOut;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(JobTelemetrySummary other) {
    _$v = other as _$JobTelemetrySummary;
  }

  @override
  void update(void Function(JobTelemetrySummaryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  JobTelemetrySummary build() => _build();

  _$JobTelemetrySummary _build() {
    final _$result = _$v ??
        _$JobTelemetrySummary._(
          cachedTokensIn: BuiltValueNullFieldError.checkNotNull(
              cachedTokensIn, r'JobTelemetrySummary', 'cachedTokensIn'),
          chunkCount: BuiltValueNullFieldError.checkNotNull(
              chunkCount, r'JobTelemetrySummary', 'chunkCount'),
          docKind: docKind,
          energyMillijoules: BuiltValueNullFieldError.checkNotNull(
              energyMillijoules, r'JobTelemetrySummary', 'energyMillijoules'),
          latencyTotalMs: BuiltValueNullFieldError.checkNotNull(
              latencyTotalMs, r'JobTelemetrySummary', 'latencyTotalMs'),
          model: model,
          provider: provider,
          scenesDetected: scenesDetected,
          scenesExtracted: scenesExtracted,
          scenesSynthesized: scenesSynthesized,
          tokensIn: BuiltValueNullFieldError.checkNotNull(
              tokensIn, r'JobTelemetrySummary', 'tokensIn'),
          tokensOut: BuiltValueNullFieldError.checkNotNull(
              tokensOut, r'JobTelemetrySummary', 'tokensOut'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
