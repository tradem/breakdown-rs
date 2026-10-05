// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'aggregate_soll_ist_diff_row.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AggregateSollIstDiffRow extends AggregateSollIstDiffRow {
  @override
  final String? actualOrder;
  @override
  final String? location;
  @override
  final bool missing;
  @override
  final bool moved;
  @override
  final String? plannedOrder;
  @override
  final bool reshotCandidate;
  @override
  final String sceneId;
  @override
  final int? sceneNumber;
  @override
  final String? scriptDay;
  @override
  final String shootingDayId;
  @override
  final String? shootingDayLabel;
  @override
  final bool skipped;

  factory _$AggregateSollIstDiffRow(
          [void Function(AggregateSollIstDiffRowBuilder)? updates]) =>
      (AggregateSollIstDiffRowBuilder()..update(updates))._build();

  _$AggregateSollIstDiffRow._(
      {this.actualOrder,
      this.location,
      required this.missing,
      required this.moved,
      this.plannedOrder,
      required this.reshotCandidate,
      required this.sceneId,
      this.sceneNumber,
      this.scriptDay,
      required this.shootingDayId,
      this.shootingDayLabel,
      required this.skipped})
      : super._();
  @override
  AggregateSollIstDiffRow rebuild(
          void Function(AggregateSollIstDiffRowBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AggregateSollIstDiffRowBuilder toBuilder() =>
      AggregateSollIstDiffRowBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AggregateSollIstDiffRow &&
        actualOrder == other.actualOrder &&
        location == other.location &&
        missing == other.missing &&
        moved == other.moved &&
        plannedOrder == other.plannedOrder &&
        reshotCandidate == other.reshotCandidate &&
        sceneId == other.sceneId &&
        sceneNumber == other.sceneNumber &&
        scriptDay == other.scriptDay &&
        shootingDayId == other.shootingDayId &&
        shootingDayLabel == other.shootingDayLabel &&
        skipped == other.skipped;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, actualOrder.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, missing.hashCode);
    _$hash = $jc(_$hash, moved.hashCode);
    _$hash = $jc(_$hash, plannedOrder.hashCode);
    _$hash = $jc(_$hash, reshotCandidate.hashCode);
    _$hash = $jc(_$hash, sceneId.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, scriptDay.hashCode);
    _$hash = $jc(_$hash, shootingDayId.hashCode);
    _$hash = $jc(_$hash, shootingDayLabel.hashCode);
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AggregateSollIstDiffRow')
          ..add('actualOrder', actualOrder)
          ..add('location', location)
          ..add('missing', missing)
          ..add('moved', moved)
          ..add('plannedOrder', plannedOrder)
          ..add('reshotCandidate', reshotCandidate)
          ..add('sceneId', sceneId)
          ..add('sceneNumber', sceneNumber)
          ..add('scriptDay', scriptDay)
          ..add('shootingDayId', shootingDayId)
          ..add('shootingDayLabel', shootingDayLabel)
          ..add('skipped', skipped))
        .toString();
  }
}

class AggregateSollIstDiffRowBuilder
    implements
        Builder<AggregateSollIstDiffRow, AggregateSollIstDiffRowBuilder> {
  _$AggregateSollIstDiffRow? _$v;

  String? _actualOrder;
  String? get actualOrder => _$this._actualOrder;
  set actualOrder(String? actualOrder) => _$this._actualOrder = actualOrder;

  String? _location;
  String? get location => _$this._location;
  set location(String? location) => _$this._location = location;

  bool? _missing;
  bool? get missing => _$this._missing;
  set missing(bool? missing) => _$this._missing = missing;

  bool? _moved;
  bool? get moved => _$this._moved;
  set moved(bool? moved) => _$this._moved = moved;

  String? _plannedOrder;
  String? get plannedOrder => _$this._plannedOrder;
  set plannedOrder(String? plannedOrder) => _$this._plannedOrder = plannedOrder;

  bool? _reshotCandidate;
  bool? get reshotCandidate => _$this._reshotCandidate;
  set reshotCandidate(bool? reshotCandidate) =>
      _$this._reshotCandidate = reshotCandidate;

  String? _sceneId;
  String? get sceneId => _$this._sceneId;
  set sceneId(String? sceneId) => _$this._sceneId = sceneId;

  int? _sceneNumber;
  int? get sceneNumber => _$this._sceneNumber;
  set sceneNumber(int? sceneNumber) => _$this._sceneNumber = sceneNumber;

  String? _scriptDay;
  String? get scriptDay => _$this._scriptDay;
  set scriptDay(String? scriptDay) => _$this._scriptDay = scriptDay;

  String? _shootingDayId;
  String? get shootingDayId => _$this._shootingDayId;
  set shootingDayId(String? shootingDayId) =>
      _$this._shootingDayId = shootingDayId;

  String? _shootingDayLabel;
  String? get shootingDayLabel => _$this._shootingDayLabel;
  set shootingDayLabel(String? shootingDayLabel) =>
      _$this._shootingDayLabel = shootingDayLabel;

  bool? _skipped;
  bool? get skipped => _$this._skipped;
  set skipped(bool? skipped) => _$this._skipped = skipped;

  AggregateSollIstDiffRowBuilder() {
    AggregateSollIstDiffRow._defaults(this);
  }

  AggregateSollIstDiffRowBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _actualOrder = $v.actualOrder;
      _location = $v.location;
      _missing = $v.missing;
      _moved = $v.moved;
      _plannedOrder = $v.plannedOrder;
      _reshotCandidate = $v.reshotCandidate;
      _sceneId = $v.sceneId;
      _sceneNumber = $v.sceneNumber;
      _scriptDay = $v.scriptDay;
      _shootingDayId = $v.shootingDayId;
      _shootingDayLabel = $v.shootingDayLabel;
      _skipped = $v.skipped;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AggregateSollIstDiffRow other) {
    _$v = other as _$AggregateSollIstDiffRow;
  }

  @override
  void update(void Function(AggregateSollIstDiffRowBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AggregateSollIstDiffRow build() => _build();

  _$AggregateSollIstDiffRow _build() {
    final _$result = _$v ??
        _$AggregateSollIstDiffRow._(
          actualOrder: actualOrder,
          location: location,
          missing: BuiltValueNullFieldError.checkNotNull(
              missing, r'AggregateSollIstDiffRow', 'missing'),
          moved: BuiltValueNullFieldError.checkNotNull(
              moved, r'AggregateSollIstDiffRow', 'moved'),
          plannedOrder: plannedOrder,
          reshotCandidate: BuiltValueNullFieldError.checkNotNull(
              reshotCandidate, r'AggregateSollIstDiffRow', 'reshotCandidate'),
          sceneId: BuiltValueNullFieldError.checkNotNull(
              sceneId, r'AggregateSollIstDiffRow', 'sceneId'),
          sceneNumber: sceneNumber,
          scriptDay: scriptDay,
          shootingDayId: BuiltValueNullFieldError.checkNotNull(
              shootingDayId, r'AggregateSollIstDiffRow', 'shootingDayId'),
          shootingDayLabel: shootingDayLabel,
          skipped: BuiltValueNullFieldError.checkNotNull(
              skipped, r'AggregateSollIstDiffRow', 'skipped'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
