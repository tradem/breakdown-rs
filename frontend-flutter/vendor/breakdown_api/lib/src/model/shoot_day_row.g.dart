// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shoot_day_row.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShootDayRow extends ShootDayRow {
  @override
  final String? actualOrder;
  @override
  final BuiltList<String> continuityPhotoIds;
  @override
  final DateTime? endDt;
  @override
  final String? location;
  @override
  final BuiltList<SerializedNote> notes;
  @override
  final String sceneId;
  @override
  final int? sceneNumber;
  @override
  final String? scriptDay;
  @override
  final DateTime? startDt;
  @override
  final SceneShootStatus status;

  factory _$ShootDayRow([void Function(ShootDayRowBuilder)? updates]) =>
      (ShootDayRowBuilder()..update(updates))._build();

  _$ShootDayRow._(
      {this.actualOrder,
      required this.continuityPhotoIds,
      this.endDt,
      this.location,
      required this.notes,
      required this.sceneId,
      this.sceneNumber,
      this.scriptDay,
      this.startDt,
      required this.status})
      : super._();
  @override
  ShootDayRow rebuild(void Function(ShootDayRowBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShootDayRowBuilder toBuilder() => ShootDayRowBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShootDayRow &&
        actualOrder == other.actualOrder &&
        continuityPhotoIds == other.continuityPhotoIds &&
        endDt == other.endDt &&
        location == other.location &&
        notes == other.notes &&
        sceneId == other.sceneId &&
        sceneNumber == other.sceneNumber &&
        scriptDay == other.scriptDay &&
        startDt == other.startDt &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, actualOrder.hashCode);
    _$hash = $jc(_$hash, continuityPhotoIds.hashCode);
    _$hash = $jc(_$hash, endDt.hashCode);
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, sceneId.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, scriptDay.hashCode);
    _$hash = $jc(_$hash, startDt.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ShootDayRow')
          ..add('actualOrder', actualOrder)
          ..add('continuityPhotoIds', continuityPhotoIds)
          ..add('endDt', endDt)
          ..add('location', location)
          ..add('notes', notes)
          ..add('sceneId', sceneId)
          ..add('sceneNumber', sceneNumber)
          ..add('scriptDay', scriptDay)
          ..add('startDt', startDt)
          ..add('status', status))
        .toString();
  }
}

class ShootDayRowBuilder implements Builder<ShootDayRow, ShootDayRowBuilder> {
  _$ShootDayRow? _$v;

  String? _actualOrder;
  String? get actualOrder => _$this._actualOrder;
  set actualOrder(String? actualOrder) => _$this._actualOrder = actualOrder;

  ListBuilder<String>? _continuityPhotoIds;
  ListBuilder<String> get continuityPhotoIds =>
      _$this._continuityPhotoIds ??= ListBuilder<String>();
  set continuityPhotoIds(ListBuilder<String>? continuityPhotoIds) =>
      _$this._continuityPhotoIds = continuityPhotoIds;

  DateTime? _endDt;
  DateTime? get endDt => _$this._endDt;
  set endDt(DateTime? endDt) => _$this._endDt = endDt;

  String? _location;
  String? get location => _$this._location;
  set location(String? location) => _$this._location = location;

  ListBuilder<SerializedNote>? _notes;
  ListBuilder<SerializedNote> get notes =>
      _$this._notes ??= ListBuilder<SerializedNote>();
  set notes(ListBuilder<SerializedNote>? notes) => _$this._notes = notes;

  String? _sceneId;
  String? get sceneId => _$this._sceneId;
  set sceneId(String? sceneId) => _$this._sceneId = sceneId;

  int? _sceneNumber;
  int? get sceneNumber => _$this._sceneNumber;
  set sceneNumber(int? sceneNumber) => _$this._sceneNumber = sceneNumber;

  String? _scriptDay;
  String? get scriptDay => _$this._scriptDay;
  set scriptDay(String? scriptDay) => _$this._scriptDay = scriptDay;

  DateTime? _startDt;
  DateTime? get startDt => _$this._startDt;
  set startDt(DateTime? startDt) => _$this._startDt = startDt;

  SceneShootStatus? _status;
  SceneShootStatus? get status => _$this._status;
  set status(SceneShootStatus? status) => _$this._status = status;

  ShootDayRowBuilder() {
    ShootDayRow._defaults(this);
  }

  ShootDayRowBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _actualOrder = $v.actualOrder;
      _continuityPhotoIds = $v.continuityPhotoIds.toBuilder();
      _endDt = $v.endDt;
      _location = $v.location;
      _notes = $v.notes.toBuilder();
      _sceneId = $v.sceneId;
      _sceneNumber = $v.sceneNumber;
      _scriptDay = $v.scriptDay;
      _startDt = $v.startDt;
      _status = $v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ShootDayRow other) {
    _$v = other as _$ShootDayRow;
  }

  @override
  void update(void Function(ShootDayRowBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShootDayRow build() => _build();

  _$ShootDayRow _build() {
    _$ShootDayRow _$result;
    try {
      _$result = _$v ??
          _$ShootDayRow._(
            actualOrder: actualOrder,
            continuityPhotoIds: continuityPhotoIds.build(),
            endDt: endDt,
            location: location,
            notes: notes.build(),
            sceneId: BuiltValueNullFieldError.checkNotNull(
                sceneId, r'ShootDayRow', 'sceneId'),
            sceneNumber: sceneNumber,
            scriptDay: scriptDay,
            startDt: startDt,
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'ShootDayRow', 'status'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'continuityPhotoIds';
        continuityPhotoIds.build();

        _$failedField = 'notes';
        notes.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ShootDayRow', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
