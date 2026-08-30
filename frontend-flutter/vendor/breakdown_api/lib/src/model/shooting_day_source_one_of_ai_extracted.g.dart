// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shooting_day_source_one_of_ai_extracted.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShootingDaySourceOneOfAiExtracted
    extends ShootingDaySourceOneOfAiExtracted {
  @override
  final double confidence;
  @override
  final String documentId;
  @override
  final String? externalRef;

  factory _$ShootingDaySourceOneOfAiExtracted(
          [void Function(ShootingDaySourceOneOfAiExtractedBuilder)? updates]) =>
      (ShootingDaySourceOneOfAiExtractedBuilder()..update(updates))._build();

  _$ShootingDaySourceOneOfAiExtracted._(
      {required this.confidence, required this.documentId, this.externalRef})
      : super._();
  @override
  ShootingDaySourceOneOfAiExtracted rebuild(
          void Function(ShootingDaySourceOneOfAiExtractedBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShootingDaySourceOneOfAiExtractedBuilder toBuilder() =>
      ShootingDaySourceOneOfAiExtractedBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShootingDaySourceOneOfAiExtracted &&
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
    return (newBuiltValueToStringHelper(r'ShootingDaySourceOneOfAiExtracted')
          ..add('confidence', confidence)
          ..add('documentId', documentId)
          ..add('externalRef', externalRef))
        .toString();
  }
}

class ShootingDaySourceOneOfAiExtractedBuilder
    implements
        Builder<ShootingDaySourceOneOfAiExtracted,
            ShootingDaySourceOneOfAiExtractedBuilder> {
  _$ShootingDaySourceOneOfAiExtracted? _$v;

  double? _confidence;
  double? get confidence => _$this._confidence;
  set confidence(double? confidence) => _$this._confidence = confidence;

  String? _documentId;
  String? get documentId => _$this._documentId;
  set documentId(String? documentId) => _$this._documentId = documentId;

  String? _externalRef;
  String? get externalRef => _$this._externalRef;
  set externalRef(String? externalRef) => _$this._externalRef = externalRef;

  ShootingDaySourceOneOfAiExtractedBuilder() {
    ShootingDaySourceOneOfAiExtracted._defaults(this);
  }

  ShootingDaySourceOneOfAiExtractedBuilder get _$this {
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
  void replace(ShootingDaySourceOneOfAiExtracted other) {
    _$v = other as _$ShootingDaySourceOneOfAiExtracted;
  }

  @override
  void update(
      void Function(ShootingDaySourceOneOfAiExtractedBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShootingDaySourceOneOfAiExtracted build() => _build();

  _$ShootingDaySourceOneOfAiExtracted _build() {
    final _$result = _$v ??
        _$ShootingDaySourceOneOfAiExtracted._(
          confidence: BuiltValueNullFieldError.checkNotNull(
              confidence, r'ShootingDaySourceOneOfAiExtracted', 'confidence'),
          documentId: BuiltValueNullFieldError.checkNotNull(
              documentId, r'ShootingDaySourceOneOfAiExtracted', 'documentId'),
          externalRef: externalRef,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
