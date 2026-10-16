// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_progress.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportProgress extends AiImportProgress {
  @override
  final int? chunk;
  @override
  final int? chunksTotal;
  @override
  final BuiltList<String>? episodesSeen;
  @override
  final AiImportStage stage;

  factory _$AiImportProgress(
          [void Function(AiImportProgressBuilder)? updates]) =>
      (AiImportProgressBuilder()..update(updates))._build();

  _$AiImportProgress._(
      {this.chunk, this.chunksTotal, this.episodesSeen, required this.stage})
      : super._();
  @override
  AiImportProgress rebuild(void Function(AiImportProgressBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportProgressBuilder toBuilder() =>
      AiImportProgressBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportProgress &&
        chunk == other.chunk &&
        chunksTotal == other.chunksTotal &&
        episodesSeen == other.episodesSeen &&
        stage == other.stage;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, chunk.hashCode);
    _$hash = $jc(_$hash, chunksTotal.hashCode);
    _$hash = $jc(_$hash, episodesSeen.hashCode);
    _$hash = $jc(_$hash, stage.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportProgress')
          ..add('chunk', chunk)
          ..add('chunksTotal', chunksTotal)
          ..add('episodesSeen', episodesSeen)
          ..add('stage', stage))
        .toString();
  }
}

class AiImportProgressBuilder
    implements Builder<AiImportProgress, AiImportProgressBuilder> {
  _$AiImportProgress? _$v;

  int? _chunk;
  int? get chunk => _$this._chunk;
  set chunk(int? chunk) => _$this._chunk = chunk;

  int? _chunksTotal;
  int? get chunksTotal => _$this._chunksTotal;
  set chunksTotal(int? chunksTotal) => _$this._chunksTotal = chunksTotal;

  ListBuilder<String>? _episodesSeen;
  ListBuilder<String> get episodesSeen =>
      _$this._episodesSeen ??= ListBuilder<String>();
  set episodesSeen(ListBuilder<String>? episodesSeen) =>
      _$this._episodesSeen = episodesSeen;

  AiImportStage? _stage;
  AiImportStage? get stage => _$this._stage;
  set stage(AiImportStage? stage) => _$this._stage = stage;

  AiImportProgressBuilder() {
    AiImportProgress._defaults(this);
  }

  AiImportProgressBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _chunk = $v.chunk;
      _chunksTotal = $v.chunksTotal;
      _episodesSeen = $v.episodesSeen?.toBuilder();
      _stage = $v.stage;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportProgress other) {
    _$v = other as _$AiImportProgress;
  }

  @override
  void update(void Function(AiImportProgressBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportProgress build() => _build();

  _$AiImportProgress _build() {
    _$AiImportProgress _$result;
    try {
      _$result = _$v ??
          _$AiImportProgress._(
            chunk: chunk,
            chunksTotal: chunksTotal,
            episodesSeen: _episodesSeen?.build(),
            stage: BuiltValueNullFieldError.checkNotNull(
                stage, r'AiImportProgress', 'stage'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'episodesSeen';
        _episodesSeen?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiImportProgress', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
