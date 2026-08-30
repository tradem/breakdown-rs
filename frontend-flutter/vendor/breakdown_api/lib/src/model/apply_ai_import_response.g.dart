// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_ai_import_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyAiImportResponse extends ApplyAiImportResponse {
  @override
  final int appliedCount;
  @override
  final int createdDays;
  @override
  final int plannedSceneShoots;

  factory _$ApplyAiImportResponse(
          [void Function(ApplyAiImportResponseBuilder)? updates]) =>
      (ApplyAiImportResponseBuilder()..update(updates))._build();

  _$ApplyAiImportResponse._(
      {required this.appliedCount,
      required this.createdDays,
      required this.plannedSceneShoots})
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
        createdDays == other.createdDays &&
        plannedSceneShoots == other.plannedSceneShoots;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appliedCount.hashCode);
    _$hash = $jc(_$hash, createdDays.hashCode);
    _$hash = $jc(_$hash, plannedSceneShoots.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyAiImportResponse')
          ..add('appliedCount', appliedCount)
          ..add('createdDays', createdDays)
          ..add('plannedSceneShoots', plannedSceneShoots))
        .toString();
  }
}

class ApplyAiImportResponseBuilder
    implements Builder<ApplyAiImportResponse, ApplyAiImportResponseBuilder> {
  _$ApplyAiImportResponse? _$v;

  int? _appliedCount;
  int? get appliedCount => _$this._appliedCount;
  set appliedCount(int? appliedCount) => _$this._appliedCount = appliedCount;

  int? _createdDays;
  int? get createdDays => _$this._createdDays;
  set createdDays(int? createdDays) => _$this._createdDays = createdDays;

  int? _plannedSceneShoots;
  int? get plannedSceneShoots => _$this._plannedSceneShoots;
  set plannedSceneShoots(int? plannedSceneShoots) =>
      _$this._plannedSceneShoots = plannedSceneShoots;

  ApplyAiImportResponseBuilder() {
    ApplyAiImportResponse._defaults(this);
  }

  ApplyAiImportResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appliedCount = $v.appliedCount;
      _createdDays = $v.createdDays;
      _plannedSceneShoots = $v.plannedSceneShoots;
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
    final _$result = _$v ??
        _$ApplyAiImportResponse._(
          appliedCount: BuiltValueNullFieldError.checkNotNull(
              appliedCount, r'ApplyAiImportResponse', 'appliedCount'),
          createdDays: BuiltValueNullFieldError.checkNotNull(
              createdDays, r'ApplyAiImportResponse', 'createdDays'),
          plannedSceneShoots: BuiltValueNullFieldError.checkNotNull(
              plannedSceneShoots,
              r'ApplyAiImportResponse',
              'plannedSceneShoots'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
