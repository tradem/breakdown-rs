// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_ai_import_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyAiImportResponse extends ApplyAiImportResponse {
  @override
  final int appliedCount;
  @override
  final int createdCharacters;
  @override
  final int createdDays;
  @override
  final int createdEpisodes;
  @override
  final int createdOutfits;
  @override
  final int createdPieces;
  @override
  final int plannedSceneShoots;
  @override
  final BuiltList<String>? skippedDayGroups;
  @override
  final BuiltList<UnappliedOutfit> unappliedOutfits;

  factory _$ApplyAiImportResponse(
          [void Function(ApplyAiImportResponseBuilder)? updates]) =>
      (ApplyAiImportResponseBuilder()..update(updates))._build();

  _$ApplyAiImportResponse._(
      {required this.appliedCount,
      required this.createdCharacters,
      required this.createdDays,
      required this.createdEpisodes,
      required this.createdOutfits,
      required this.createdPieces,
      required this.plannedSceneShoots,
      this.skippedDayGroups,
      required this.unappliedOutfits})
      : super._();
  @override
  ApplyAiImportResponse rebuild(
          void Function(ApplyAiImportResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyAiImportResponseBuilder toBuilder() =>
      ApplyAiImportResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyAiImportResponse &&
        appliedCount == other.appliedCount &&
        createdCharacters == other.createdCharacters &&
        createdDays == other.createdDays &&
        createdEpisodes == other.createdEpisodes &&
        createdOutfits == other.createdOutfits &&
        createdPieces == other.createdPieces &&
        plannedSceneShoots == other.plannedSceneShoots &&
        skippedDayGroups == other.skippedDayGroups &&
        unappliedOutfits == other.unappliedOutfits;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appliedCount.hashCode);
    _$hash = $jc(_$hash, createdCharacters.hashCode);
    _$hash = $jc(_$hash, createdDays.hashCode);
    _$hash = $jc(_$hash, createdEpisodes.hashCode);
    _$hash = $jc(_$hash, createdOutfits.hashCode);
    _$hash = $jc(_$hash, createdPieces.hashCode);
    _$hash = $jc(_$hash, plannedSceneShoots.hashCode);
    _$hash = $jc(_$hash, skippedDayGroups.hashCode);
    _$hash = $jc(_$hash, unappliedOutfits.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyAiImportResponse')
          ..add('appliedCount', appliedCount)
          ..add('createdCharacters', createdCharacters)
          ..add('createdDays', createdDays)
          ..add('createdEpisodes', createdEpisodes)
          ..add('createdOutfits', createdOutfits)
          ..add('createdPieces', createdPieces)
          ..add('plannedSceneShoots', plannedSceneShoots)
          ..add('skippedDayGroups', skippedDayGroups)
          ..add('unappliedOutfits', unappliedOutfits))
        .toString();
  }
}

class ApplyAiImportResponseBuilder
    implements Builder<ApplyAiImportResponse, ApplyAiImportResponseBuilder> {
  _$ApplyAiImportResponse? _$v;

  int? _appliedCount;
  int? get appliedCount => _$this._appliedCount;
  set appliedCount(int? appliedCount) => _$this._appliedCount = appliedCount;

  int? _createdCharacters;
  int? get createdCharacters => _$this._createdCharacters;
  set createdCharacters(int? createdCharacters) =>
      _$this._createdCharacters = createdCharacters;

  int? _createdDays;
  int? get createdDays => _$this._createdDays;
  set createdDays(int? createdDays) => _$this._createdDays = createdDays;

  int? _createdEpisodes;
  int? get createdEpisodes => _$this._createdEpisodes;
  set createdEpisodes(int? createdEpisodes) =>
      _$this._createdEpisodes = createdEpisodes;

  int? _createdOutfits;
  int? get createdOutfits => _$this._createdOutfits;
  set createdOutfits(int? createdOutfits) =>
      _$this._createdOutfits = createdOutfits;

  int? _createdPieces;
  int? get createdPieces => _$this._createdPieces;
  set createdPieces(int? createdPieces) =>
      _$this._createdPieces = createdPieces;

  int? _plannedSceneShoots;
  int? get plannedSceneShoots => _$this._plannedSceneShoots;
  set plannedSceneShoots(int? plannedSceneShoots) =>
      _$this._plannedSceneShoots = plannedSceneShoots;

  ListBuilder<String>? _skippedDayGroups;
  ListBuilder<String> get skippedDayGroups =>
      _$this._skippedDayGroups ??= ListBuilder<String>();
  set skippedDayGroups(ListBuilder<String>? skippedDayGroups) =>
      _$this._skippedDayGroups = skippedDayGroups;

  ListBuilder<UnappliedOutfit>? _unappliedOutfits;
  ListBuilder<UnappliedOutfit> get unappliedOutfits =>
      _$this._unappliedOutfits ??= ListBuilder<UnappliedOutfit>();
  set unappliedOutfits(ListBuilder<UnappliedOutfit>? unappliedOutfits) =>
      _$this._unappliedOutfits = unappliedOutfits;

  ApplyAiImportResponseBuilder() {
    ApplyAiImportResponse._defaults(this);
  }

  ApplyAiImportResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appliedCount = $v.appliedCount;
      _createdCharacters = $v.createdCharacters;
      _createdDays = $v.createdDays;
      _createdEpisodes = $v.createdEpisodes;
      _createdOutfits = $v.createdOutfits;
      _createdPieces = $v.createdPieces;
      _plannedSceneShoots = $v.plannedSceneShoots;
      _skippedDayGroups = $v.skippedDayGroups?.toBuilder();
      _unappliedOutfits = $v.unappliedOutfits.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyAiImportResponse other) {
    _$v = other as _$ApplyAiImportResponse;
  }

  @override
  void update(void Function(ApplyAiImportResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyAiImportResponse build() => _build();

  _$ApplyAiImportResponse _build() {
    _$ApplyAiImportResponse _$result;
    try {
      _$result = _$v ??
          _$ApplyAiImportResponse._(
            appliedCount: BuiltValueNullFieldError.checkNotNull(
                appliedCount, r'ApplyAiImportResponse', 'appliedCount'),
            createdCharacters: BuiltValueNullFieldError.checkNotNull(
                createdCharacters,
                r'ApplyAiImportResponse',
                'createdCharacters'),
            createdDays: BuiltValueNullFieldError.checkNotNull(
                createdDays, r'ApplyAiImportResponse', 'createdDays'),
            createdEpisodes: BuiltValueNullFieldError.checkNotNull(
                createdEpisodes, r'ApplyAiImportResponse', 'createdEpisodes'),
            createdOutfits: BuiltValueNullFieldError.checkNotNull(
                createdOutfits, r'ApplyAiImportResponse', 'createdOutfits'),
            createdPieces: BuiltValueNullFieldError.checkNotNull(
                createdPieces, r'ApplyAiImportResponse', 'createdPieces'),
            plannedSceneShoots: BuiltValueNullFieldError.checkNotNull(
                plannedSceneShoots,
                r'ApplyAiImportResponse',
                'plannedSceneShoots'),
            skippedDayGroups: _skippedDayGroups?.build(),
            unappliedOutfits: unappliedOutfits.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'skippedDayGroups';
        _skippedDayGroups?.build();
        _$failedField = 'unappliedOutfits';
        unappliedOutfits.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyAiImportResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
