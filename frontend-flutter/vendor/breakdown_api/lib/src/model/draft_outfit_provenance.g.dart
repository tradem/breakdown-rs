// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit_provenance.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftOutfitProvenance extends DraftOutfitProvenance {
  @override
  final double confidence;
  @override
  final String? sourceDraftRef;
  @override
  final int? sourceSceneNumber;

  factory _$DraftOutfitProvenance(
          [void Function(DraftOutfitProvenanceBuilder)? updates]) =>
      (DraftOutfitProvenanceBuilder()..update(updates))._build();

  _$DraftOutfitProvenance._(
      {required this.confidence, this.sourceDraftRef, this.sourceSceneNumber})
      : super._();
  @override
  DraftOutfitProvenance rebuild(
          void Function(DraftOutfitProvenanceBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftOutfitProvenanceBuilder toBuilder() =>
      DraftOutfitProvenanceBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftOutfitProvenance &&
        confidence == other.confidence &&
        sourceDraftRef == other.sourceDraftRef &&
        sourceSceneNumber == other.sourceSceneNumber;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, confidence.hashCode);
    _$hash = $jc(_$hash, sourceDraftRef.hashCode);
    _$hash = $jc(_$hash, sourceSceneNumber.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftOutfitProvenance')
          ..add('confidence', confidence)
          ..add('sourceDraftRef', sourceDraftRef)
          ..add('sourceSceneNumber', sourceSceneNumber))
        .toString();
  }
}

class DraftOutfitProvenanceBuilder
    implements Builder<DraftOutfitProvenance, DraftOutfitProvenanceBuilder> {
  _$DraftOutfitProvenance? _$v;

  double? _confidence;
  double? get confidence => _$this._confidence;
  set confidence(double? confidence) => _$this._confidence = confidence;

  String? _sourceDraftRef;
  String? get sourceDraftRef => _$this._sourceDraftRef;
  set sourceDraftRef(String? sourceDraftRef) =>
      _$this._sourceDraftRef = sourceDraftRef;

  int? _sourceSceneNumber;
  int? get sourceSceneNumber => _$this._sourceSceneNumber;
  set sourceSceneNumber(int? sourceSceneNumber) =>
      _$this._sourceSceneNumber = sourceSceneNumber;

  DraftOutfitProvenanceBuilder() {
    DraftOutfitProvenance._defaults(this);
  }

  DraftOutfitProvenanceBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _confidence = $v.confidence;
      _sourceDraftRef = $v.sourceDraftRef;
      _sourceSceneNumber = $v.sourceSceneNumber;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftOutfitProvenance other) {
    _$v = other as _$DraftOutfitProvenance;
  }

  @override
  void update(void Function(DraftOutfitProvenanceBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftOutfitProvenance build() => _build();

  _$DraftOutfitProvenance _build() {
    final _$result = _$v ??
        _$DraftOutfitProvenance._(
          confidence: BuiltValueNullFieldError.checkNotNull(
              confidence, r'DraftOutfitProvenance', 'confidence'),
          sourceDraftRef: sourceDraftRef,
          sourceSceneNumber: sourceSceneNumber,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
