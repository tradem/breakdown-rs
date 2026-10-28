// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit_origin_one_of_continued_from_scene.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftOutfitOriginOneOfContinuedFromScene
    extends DraftOutfitOriginOneOfContinuedFromScene {
  @override
  final double confidence;
  @override
  final String sourceDraftRef;
  @override
  final int? sourceSceneNumber;

  factory _$DraftOutfitOriginOneOfContinuedFromScene(
          [void Function(DraftOutfitOriginOneOfContinuedFromSceneBuilder)?
              updates]) =>
      (DraftOutfitOriginOneOfContinuedFromSceneBuilder()..update(updates))
          ._build();

  _$DraftOutfitOriginOneOfContinuedFromScene._(
      {required this.confidence,
      required this.sourceDraftRef,
      this.sourceSceneNumber})
      : super._();
  @override
  DraftOutfitOriginOneOfContinuedFromScene rebuild(
          void Function(DraftOutfitOriginOneOfContinuedFromSceneBuilder)
              updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftOutfitOriginOneOfContinuedFromSceneBuilder toBuilder() =>
      DraftOutfitOriginOneOfContinuedFromSceneBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftOutfitOriginOneOfContinuedFromScene &&
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
    return (newBuiltValueToStringHelper(
            r'DraftOutfitOriginOneOfContinuedFromScene')
          ..add('confidence', confidence)
          ..add('sourceDraftRef', sourceDraftRef)
          ..add('sourceSceneNumber', sourceSceneNumber))
        .toString();
  }
}

class DraftOutfitOriginOneOfContinuedFromSceneBuilder
    implements
        Builder<DraftOutfitOriginOneOfContinuedFromScene,
            DraftOutfitOriginOneOfContinuedFromSceneBuilder> {
  _$DraftOutfitOriginOneOfContinuedFromScene? _$v;

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

  DraftOutfitOriginOneOfContinuedFromSceneBuilder() {
    DraftOutfitOriginOneOfContinuedFromScene._defaults(this);
  }

  DraftOutfitOriginOneOfContinuedFromSceneBuilder get _$this {
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
  void replace(DraftOutfitOriginOneOfContinuedFromScene other) {
    _$v = other as _$DraftOutfitOriginOneOfContinuedFromScene;
  }

  @override
  void update(
      void Function(DraftOutfitOriginOneOfContinuedFromSceneBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftOutfitOriginOneOfContinuedFromScene build() => _build();

  _$DraftOutfitOriginOneOfContinuedFromScene _build() {
    final _$result = _$v ??
        _$DraftOutfitOriginOneOfContinuedFromScene._(
          confidence: BuiltValueNullFieldError.checkNotNull(confidence,
              r'DraftOutfitOriginOneOfContinuedFromScene', 'confidence'),
          sourceDraftRef: BuiltValueNullFieldError.checkNotNull(sourceDraftRef,
              r'DraftOutfitOriginOneOfContinuedFromScene', 'sourceDraftRef'),
          sourceSceneNumber: sourceSceneNumber,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
