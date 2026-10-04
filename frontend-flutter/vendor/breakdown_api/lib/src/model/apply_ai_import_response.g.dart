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
  final int createdCostumes;
  @override
  final int createdDays;
  @override
  final int createdEpisodes;
  @override
  final int plannedSceneShoots;
  @override
  final BuiltList<UnappliedCostume> unappliedCostumes;

  factory _$ApplyAiImportResponse(
          [void Function(ApplyAiImportResponseBuilder)? updates]) =>
      (ApplyAiImportResponseBuilder()..update(updates))._build();

  _$ApplyAiImportResponse._(
      {required this.appliedCount,
      required this.createdCharacters,
      required this.createdCostumes,
      required this.createdDays,
      required this.createdEpisodes,
      required this.plannedSceneShoots,
      required this.unappliedCostumes})
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
        createdCostumes == other.createdCostumes &&
        createdDays == other.createdDays &&
        createdEpisodes == other.createdEpisodes &&
        plannedSceneShoots == other.plannedSceneShoots &&
        unappliedCostumes == other.unappliedCostumes;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appliedCount.hashCode);
    _$hash = $jc(_$hash, createdCharacters.hashCode);
    _$hash = $jc(_$hash, createdCostumes.hashCode);
    _$hash = $jc(_$hash, createdDays.hashCode);
    _$hash = $jc(_$hash, createdEpisodes.hashCode);
    _$hash = $jc(_$hash, plannedSceneShoots.hashCode);
    _$hash = $jc(_$hash, unappliedCostumes.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyAiImportResponse')
          ..add('appliedCount', appliedCount)
          ..add('createdCharacters', createdCharacters)
          ..add('createdCostumes', createdCostumes)
          ..add('createdDays', createdDays)
          ..add('createdEpisodes', createdEpisodes)
          ..add('plannedSceneShoots', plannedSceneShoots)
          ..add('unappliedCostumes', unappliedCostumes))
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

  int? _createdCostumes;
  int? get createdCostumes => _$this._createdCostumes;
  set createdCostumes(int? createdCostumes) =>
      _$this._createdCostumes = createdCostumes;

  int? _createdDays;
  int? get createdDays => _$this._createdDays;
  set createdDays(int? createdDays) => _$this._createdDays = createdDays;

  int? _createdEpisodes;
  int? get createdEpisodes => _$this._createdEpisodes;
  set createdEpisodes(int? createdEpisodes) =>
      _$this._createdEpisodes = createdEpisodes;

  int? _plannedSceneShoots;
  int? get plannedSceneShoots => _$this._plannedSceneShoots;
  set plannedSceneShoots(int? plannedSceneShoots) =>
      _$this._plannedSceneShoots = plannedSceneShoots;

  ListBuilder<UnappliedCostume>? _unappliedCostumes;
  ListBuilder<UnappliedCostume> get unappliedCostumes =>
      _$this._unappliedCostumes ??= ListBuilder<UnappliedCostume>();
  set unappliedCostumes(ListBuilder<UnappliedCostume>? unappliedCostumes) =>
      _$this._unappliedCostumes = unappliedCostumes;

  ApplyAiImportResponseBuilder() {
    ApplyAiImportResponse._defaults(this);
  }

  ApplyAiImportResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appliedCount = $v.appliedCount;
      _createdCharacters = $v.createdCharacters;
      _createdCostumes = $v.createdCostumes;
      _createdDays = $v.createdDays;
      _createdEpisodes = $v.createdEpisodes;
      _plannedSceneShoots = $v.plannedSceneShoots;
      _unappliedCostumes = $v.unappliedCostumes.toBuilder();
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
            createdCostumes: BuiltValueNullFieldError.checkNotNull(
                createdCostumes, r'ApplyAiImportResponse', 'createdCostumes'),
            createdDays: BuiltValueNullFieldError.checkNotNull(
                createdDays, r'ApplyAiImportResponse', 'createdDays'),
            createdEpisodes: BuiltValueNullFieldError.checkNotNull(
                createdEpisodes, r'ApplyAiImportResponse', 'createdEpisodes'),
            plannedSceneShoots: BuiltValueNullFieldError.checkNotNull(
                plannedSceneShoots,
                r'ApplyAiImportResponse',
                'plannedSceneShoots'),
            unappliedCostumes: unappliedCostumes.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'unappliedCostumes';
        unappliedCostumes.build();
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
