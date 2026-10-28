// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'outfit_continuity_selection.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$OutfitContinuitySelection extends OutfitContinuitySelection {
  @override
  final OutfitContinuityCandidate candidate;
  @override
  final String characterIdentity;
  @override
  final int sceneIndex;

  factory _$OutfitContinuitySelection(
          [void Function(OutfitContinuitySelectionBuilder)? updates]) =>
      (OutfitContinuitySelectionBuilder()..update(updates))._build();

  _$OutfitContinuitySelection._(
      {required this.candidate,
      required this.characterIdentity,
      required this.sceneIndex})
      : super._();
  @override
  OutfitContinuitySelection rebuild(
          void Function(OutfitContinuitySelectionBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  OutfitContinuitySelectionBuilder toBuilder() =>
      OutfitContinuitySelectionBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is OutfitContinuitySelection &&
        candidate == other.candidate &&
        characterIdentity == other.characterIdentity &&
        sceneIndex == other.sceneIndex;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, candidate.hashCode);
    _$hash = $jc(_$hash, characterIdentity.hashCode);
    _$hash = $jc(_$hash, sceneIndex.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'OutfitContinuitySelection')
          ..add('candidate', candidate)
          ..add('characterIdentity', characterIdentity)
          ..add('sceneIndex', sceneIndex))
        .toString();
  }
}

class OutfitContinuitySelectionBuilder
    implements
        Builder<OutfitContinuitySelection, OutfitContinuitySelectionBuilder> {
  _$OutfitContinuitySelection? _$v;

  OutfitContinuityCandidate? _candidate;
  OutfitContinuityCandidate? get candidate => _$this._candidate;
  set candidate(OutfitContinuityCandidate? candidate) =>
      _$this._candidate = candidate;

  String? _characterIdentity;
  String? get characterIdentity => _$this._characterIdentity;
  set characterIdentity(String? characterIdentity) =>
      _$this._characterIdentity = characterIdentity;

  int? _sceneIndex;
  int? get sceneIndex => _$this._sceneIndex;
  set sceneIndex(int? sceneIndex) => _$this._sceneIndex = sceneIndex;

  OutfitContinuitySelectionBuilder() {
    OutfitContinuitySelection._defaults(this);
  }

  OutfitContinuitySelectionBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _candidate = $v.candidate;
      _characterIdentity = $v.characterIdentity;
      _sceneIndex = $v.sceneIndex;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(OutfitContinuitySelection other) {
    _$v = other as _$OutfitContinuitySelection;
  }

  @override
  void update(void Function(OutfitContinuitySelectionBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  OutfitContinuitySelection build() => _build();

  _$OutfitContinuitySelection _build() {
    final _$result = _$v ??
        _$OutfitContinuitySelection._(
          candidate: BuiltValueNullFieldError.checkNotNull(
              candidate, r'OutfitContinuitySelection', 'candidate'),
          characterIdentity: BuiltValueNullFieldError.checkNotNull(
              characterIdentity,
              r'OutfitContinuitySelection',
              'characterIdentity'),
          sceneIndex: BuiltValueNullFieldError.checkNotNull(
              sceneIndex, r'OutfitContinuitySelection', 'sceneIndex'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
