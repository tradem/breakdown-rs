// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_source_one_of_ai_extracted.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneSourceOneOfAiExtracted extends SceneSourceOneOfAiExtracted {
  @override
  final double? confidence;
  @override
  final String documentId;
  @override
  final String? externalRef;

  factory _$SceneSourceOneOfAiExtracted(
          [void Function(SceneSourceOneOfAiExtractedBuilder)? updates]) =>
      (SceneSourceOneOfAiExtractedBuilder()..update(updates))._build();

  _$SceneSourceOneOfAiExtracted._(
      {this.confidence, required this.documentId, this.externalRef})
      : super._();
  @override
  SceneSourceOneOfAiExtracted rebuild(
          void Function(SceneSourceOneOfAiExtractedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneSourceOneOfAiExtractedBuilder toBuilder() =>
      SceneSourceOneOfAiExtractedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneSourceOneOfAiExtracted &&
        confidence == other.confidence &&
        documentId == other.documentId &&
        externalRef == other.externalRef;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, confidence.hashCode);
    _$hash = $jc(_$hash, documentId.hashCode);
    _$hash = $jc(_$hash, externalRef.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneSourceOneOfAiExtracted')
          ..add('confidence', confidence)
          ..add('documentId', documentId)
          ..add('externalRef', externalRef))
        .toString();
  }
}

class SceneSourceOneOfAiExtractedBuilder
    implements
        Builder<SceneSourceOneOfAiExtracted,
            SceneSourceOneOfAiExtractedBuilder> {
  _$SceneSourceOneOfAiExtracted? _$v;

  double? _confidence;
  double? get confidence => _$this._confidence;
  set confidence(double? confidence) => _$this._confidence = confidence;

  String? _documentId;
  String? get documentId => _$this._documentId;
  set documentId(String? documentId) => _$this._documentId = documentId;

  String? _externalRef;
  String? get externalRef => _$this._externalRef;
  set externalRef(String? externalRef) => _$this._externalRef = externalRef;

  SceneSourceOneOfAiExtractedBuilder() {
    SceneSourceOneOfAiExtracted._defaults(this);
  }

  SceneSourceOneOfAiExtractedBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _confidence = $v.confidence;
      _documentId = $v.documentId;
      _externalRef = $v.externalRef;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneSourceOneOfAiExtracted other) {
    _$v = other as _$SceneSourceOneOfAiExtracted;
  }

  @override
  void update(void Function(SceneSourceOneOfAiExtractedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneSourceOneOfAiExtracted build() => _build();

  _$SceneSourceOneOfAiExtracted _build() {
    final _$result = _$v ??
        _$SceneSourceOneOfAiExtracted._(
          confidence: confidence,
          documentId: BuiltValueNullFieldError.checkNotNull(
              documentId, r'SceneSourceOneOfAiExtracted', 'documentId'),
          externalRef: externalRef,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
