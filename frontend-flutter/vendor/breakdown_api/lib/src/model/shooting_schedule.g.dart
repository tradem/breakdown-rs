// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shooting_schedule.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShootingSchedule extends ShootingSchedule {
  @override
  final String? blockId;
  @override
  final BuiltList<ShootingScheduleRow> rows;

  factory _$ShootingSchedule(
          [void Function(ShootingScheduleBuilder)? updates]) =>
      (ShootingScheduleBuilder()..update(updates))._build();

  _$ShootingSchedule._({this.blockId, required this.rows}) : super._();
  @override
  ShootingSchedule rebuild(void Function(ShootingScheduleBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShootingScheduleBuilder toBuilder() =>
      ShootingScheduleBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShootingSchedule &&
        blockId == other.blockId &&
        rows == other.rows;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jc(_$hash, rows.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ShootingSchedule')
          ..add('blockId', blockId)
          ..add('rows', rows))
        .toString();
  }
}

class ShootingScheduleBuilder
    implements Builder<ShootingSchedule, ShootingScheduleBuilder> {
  _$ShootingSchedule? _$v;

  String? _blockId;
  String? get blockId => _$this._blockId;
  set blockId(String? blockId) => _$this._blockId = blockId;

  ListBuilder<ShootingScheduleRow>? _rows;
  ListBuilder<ShootingScheduleRow> get rows =>
      _$this._rows ??= ListBuilder<ShootingScheduleRow>();
  set rows(ListBuilder<ShootingScheduleRow>? rows) => _$this._rows = rows;

  ShootingScheduleBuilder() {
    ShootingSchedule._defaults(this);
  }

  ShootingScheduleBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _blockId = $v.blockId;
      _rows = $v.rows.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ShootingSchedule other) {
    _$v = other as _$ShootingSchedule;
  }

  @override
  void update(void Function(ShootingScheduleBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShootingSchedule build() => _build();

  _$ShootingSchedule _build() {
    _$ShootingSchedule _$result;
    try {
      _$result = _$v ??
          _$ShootingSchedule._(
            blockId: blockId,
            rows: rows.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rows';
        rows.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ShootingSchedule', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
