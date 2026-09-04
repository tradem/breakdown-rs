// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shooting_schedule_row.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShootingScheduleRow extends ShootingScheduleRow {
  @override
  final Date? date;
  @override
  final String? location;
  @override
  final int? order;
  @override
  final String rowRef;
  @override
  final int? sceneNumber;
  @override
  final String? shootingDayLabel;

  factory _$ShootingScheduleRow(
          [void Function(ShootingScheduleRowBuilder)? updates]) =>
      (ShootingScheduleRowBuilder()..update(updates))._build();

  _$ShootingScheduleRow._(
      {this.date,
      this.location,
      this.order,
      required this.rowRef,
      this.sceneNumber,
      this.shootingDayLabel})
      : super._();
  @override
  ShootingScheduleRow rebuild(
          void Function(ShootingScheduleRowBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShootingScheduleRowBuilder toBuilder() =>
      ShootingScheduleRowBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShootingScheduleRow &&
        date == other.date &&
        location == other.location &&
        order == other.order &&
        rowRef == other.rowRef &&
        sceneNumber == other.sceneNumber &&
        shootingDayLabel == other.shootingDayLabel;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, order.hashCode);
    _$hash = $jc(_$hash, rowRef.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, shootingDayLabel.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ShootingScheduleRow')
          ..add('date', date)
          ..add('location', location)
          ..add('order', order)
          ..add('rowRef', rowRef)
          ..add('sceneNumber', sceneNumber)
          ..add('shootingDayLabel', shootingDayLabel))
        .toString();
  }
}

class ShootingScheduleRowBuilder
    implements Builder<ShootingScheduleRow, ShootingScheduleRowBuilder> {
  _$ShootingScheduleRow? _$v;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  String? _location;
  String? get location => _$this._location;
  set location(String? location) => _$this._location = location;

  int? _order;
  int? get order => _$this._order;
  set order(int? order) => _$this._order = order;

  String? _rowRef;
  String? get rowRef => _$this._rowRef;
  set rowRef(String? rowRef) => _$this._rowRef = rowRef;

  int? _sceneNumber;
  int? get sceneNumber => _$this._sceneNumber;
  set sceneNumber(int? sceneNumber) => _$this._sceneNumber = sceneNumber;

  String? _shootingDayLabel;
  String? get shootingDayLabel => _$this._shootingDayLabel;
  set shootingDayLabel(String? shootingDayLabel) =>
      _$this._shootingDayLabel = shootingDayLabel;

  ShootingScheduleRowBuilder() {
    ShootingScheduleRow._defaults(this);
  }

  ShootingScheduleRowBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _date = $v.date;
      _location = $v.location;
      _order = $v.order;
      _rowRef = $v.rowRef;
      _sceneNumber = $v.sceneNumber;
      _shootingDayLabel = $v.shootingDayLabel;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ShootingScheduleRow other) {
    _$v = other as _$ShootingScheduleRow;
  }

  @override
  void update(void Function(ShootingScheduleRowBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShootingScheduleRow build() => _build();

  _$ShootingScheduleRow _build() {
    final _$result = _$v ??
        _$ShootingScheduleRow._(
          date: date,
          location: location,
          order: order,
          rowRef: BuiltValueNullFieldError.checkNotNull(
              rowRef, r'ShootingScheduleRow', 'rowRef'),
          sceneNumber: sceneNumber,
          shootingDayLabel: shootingDayLabel,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
