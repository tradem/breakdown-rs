// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'soll_ist_diff_row.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SollIstDiffRow extends SollIstDiffRow {
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
  final bool skipped;

  factory _$SollIstDiffRow([void Function(SollIstDiffRowBuilder)? updates]) =>
      (SollIstDiffRowBuilder()..update(updates))._build();

  _$SollIstDiffRow._(
      {this.actualOrder,
      this.location,
      required this.missing,
      required this.moved,
      this.plannedOrder,
      required this.reshotCandidate,
      required this.sceneId,
      this.sceneNumber,
      this.scriptDay,
      required this.skipped})
      : super._();
  @override
  SollIstDiffRow rebuild(void Function(SollIstDiffRowBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SollIstDiffRowBuilder toBuilder() => SollIstDiffRowBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SollIstDiffRow &&
        actualOrder == other.actualOrder &&
        location == other.location &&
        missing == other.missing &&
        moved == other.moved &&
        plannedOrder == other.plannedOrder &&
        reshotCandidate == other.reshotCandidate &&
        sceneId == other.sceneId &&
        sceneNumber == other.sceneNumber &&
        scriptDay == other.scriptDay &&
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
    _$hash = $jc(_$hash, skipped.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SollIstDiffRow')
          ..add('actualOrder', actualOrder)
          ..add('location', location)
          ..add('missing', missing)
          ..add('moved', moved)
          ..add('plannedOrder', plannedOrder)
          ..add('reshotCandidate', reshotCandidate)
          ..add('sceneId', sceneId)
          ..add('sceneNumber', sceneNumber)
          ..add('scriptDay', scriptDay)
          ..add('skipped', skipped))
        .toString();
  }
}

class SollIstDiffRowBuilder
    implements Builder<SollIstDiffRow, SollIstDiffRowBuilder> {
  _$SollIstDiffRow? _$v;

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

  bool? _skipped;
  bool? get skipped => _$this._skipped;
  set skipped(bool? skipped) => _$this._skipped = skipped;

  SollIstDiffRowBuilder() {
    SollIstDiffRow._defaults(this);
  }

  SollIstDiffRowBuilder get _$this {
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
      _skipped = $v.skipped;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SollIstDiffRow other) {
    _$v = other as _$SollIstDiffRow;
  }

  @override
  void update(void Function(SollIstDiffRowBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SollIstDiffRow build() => _build();

  _$SollIstDiffRow _build() {
    final _$result = _$v ??
        _$SollIstDiffRow._(
          actualOrder: actualOrder,
          location: location,
          missing: BuiltValueNullFieldError.checkNotNull(
              missing, r'SollIstDiffRow', 'missing'),
          moved: BuiltValueNullFieldError.checkNotNull(
              moved, r'SollIstDiffRow', 'moved'),
          plannedOrder: plannedOrder,
          reshotCandidate: BuiltValueNullFieldError.checkNotNull(
              reshotCandidate, r'SollIstDiffRow', 'reshotCandidate'),
          sceneId: BuiltValueNullFieldError.checkNotNull(
              sceneId, r'SollIstDiffRow', 'sceneId'),
          sceneNumber: sceneNumber,
          scriptDay: scriptDay,
          skipped: BuiltValueNullFieldError.checkNotNull(
              skipped, r'SollIstDiffRow', 'skipped'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
