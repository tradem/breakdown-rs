// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_outfit_candidate.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftOutfitCandidate extends DraftOutfitCandidate {
  @override
  final double confidence;
  @override
  final String name;
  @override
  final DraftOutfitOrigin origin;
  @override
  final String sourceDraftRef;
  @override
  final int? sourceSceneNumber;

  factory _$DraftOutfitCandidate(
          [void Function(DraftOutfitCandidateBuilder)? updates]) =>
      (DraftOutfitCandidateBuilder()..update(updates))._build();

  _$DraftOutfitCandidate._(
      {required this.confidence,
      required this.name,
      required this.origin,
      required this.sourceDraftRef,
      this.sourceSceneNumber})
      : super._();
  @override
  DraftOutfitCandidate rebuild(
          void Function(DraftOutfitCandidateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftOutfitCandidateBuilder toBuilder() =>
      DraftOutfitCandidateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftOutfitCandidate &&
        confidence == other.confidence &&
        name == other.name &&
        origin == other.origin &&
        sourceDraftRef == other.sourceDraftRef &&
        sourceSceneNumber == other.sourceSceneNumber;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, confidence.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, origin.hashCode);
    _$hash = $jc(_$hash, sourceDraftRef.hashCode);
    _$hash = $jc(_$hash, sourceSceneNumber.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftOutfitCandidate')
          ..add('confidence', confidence)
          ..add('name', name)
          ..add('origin', origin)
          ..add('sourceDraftRef', sourceDraftRef)
          ..add('sourceSceneNumber', sourceSceneNumber))
        .toString();
  }
}

class DraftOutfitCandidateBuilder
    implements Builder<DraftOutfitCandidate, DraftOutfitCandidateBuilder> {
  _$DraftOutfitCandidate? _$v;

  double? _confidence;
  double? get confidence => _$this._confidence;
  set confidence(double? confidence) => _$this._confidence = confidence;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  DraftOutfitOrigin? _origin;
  DraftOutfitOrigin? get origin => _$this._origin;
  set origin(DraftOutfitOrigin? origin) => _$this._origin = origin;

  String? _sourceDraftRef;
  String? get sourceDraftRef => _$this._sourceDraftRef;
  set sourceDraftRef(String? sourceDraftRef) =>
      _$this._sourceDraftRef = sourceDraftRef;

  int? _sourceSceneNumber;
  int? get sourceSceneNumber => _$this._sourceSceneNumber;
  set sourceSceneNumber(int? sourceSceneNumber) =>
      _$this._sourceSceneNumber = sourceSceneNumber;

  DraftOutfitCandidateBuilder() {
    DraftOutfitCandidate._defaults(this);
  }

  DraftOutfitCandidateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _confidence = $v.confidence;
      _name = $v.name;
      _origin = $v.origin;
      _sourceDraftRef = $v.sourceDraftRef;
      _sourceSceneNumber = $v.sourceSceneNumber;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftOutfitCandidate other) {
    _$v = other as _$DraftOutfitCandidate;
  }

  @override
  void update(void Function(DraftOutfitCandidateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftOutfitCandidate build() => _build();

  _$DraftOutfitCandidate _build() {
    final _$result = _$v ??
        _$DraftOutfitCandidate._(
          confidence: BuiltValueNullFieldError.checkNotNull(
              confidence, r'DraftOutfitCandidate', 'confidence'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'DraftOutfitCandidate', 'name'),
          origin: BuiltValueNullFieldError.checkNotNull(
              origin, r'DraftOutfitCandidate', 'origin'),
          sourceDraftRef: BuiltValueNullFieldError.checkNotNull(
              sourceDraftRef, r'DraftOutfitCandidate', 'sourceDraftRef'),
          sourceSceneNumber: sourceSceneNumber,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
