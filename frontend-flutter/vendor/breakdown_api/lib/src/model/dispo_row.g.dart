// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dispo_row.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DispoRow extends DispoRow {
  @override
  final String? location;
  @override
  final String? mood;
  @override
  final String plannedOrder;
  @override
  final String sceneId;
  @override
  final int? sceneNumber;
  @override
  final String? scriptDay;
  @override
  final String? summary;

  factory _$DispoRow([void Function(DispoRowBuilder)? updates]) =>
      (DispoRowBuilder()..update(updates))._build();

  _$DispoRow._(
      {this.location,
      this.mood,
      required this.plannedOrder,
      required this.sceneId,
      this.sceneNumber,
      this.scriptDay,
      this.summary})
      : super._();
  @override
  DispoRow rebuild(void Function(DispoRowBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DispoRowBuilder toBuilder() => DispoRowBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DispoRow &&
        location == other.location &&
        mood == other.mood &&
        plannedOrder == other.plannedOrder &&
        sceneId == other.sceneId &&
        sceneNumber == other.sceneNumber &&
        scriptDay == other.scriptDay &&
        summary == other.summary;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, location.hashCode);
    _$hash = $jc(_$hash, mood.hashCode);
    _$hash = $jc(_$hash, plannedOrder.hashCode);
    _$hash = $jc(_$hash, sceneId.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, scriptDay.hashCode);
    _$hash = $jc(_$hash, summary.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DispoRow')
          ..add('location', location)
          ..add('mood', mood)
          ..add('plannedOrder', plannedOrder)
          ..add('sceneId', sceneId)
          ..add('sceneNumber', sceneNumber)
          ..add('scriptDay', scriptDay)
          ..add('summary', summary))
        .toString();
  }
}

class DispoRowBuilder implements Builder<DispoRow, DispoRowBuilder> {
  _$DispoRow? _$v;

  String? _location;
  String? get location => _$this._location;
  set location(String? location) => _$this._location = location;

  String? _mood;
  String? get mood => _$this._mood;
  set mood(String? mood) => _$this._mood = mood;

  String? _plannedOrder;
  String? get plannedOrder => _$this._plannedOrder;
  set plannedOrder(String? plannedOrder) => _$this._plannedOrder = plannedOrder;

  String? _sceneId;
  String? get sceneId => _$this._sceneId;
  set sceneId(String? sceneId) => _$this._sceneId = sceneId;

  int? _sceneNumber;
  int? get sceneNumber => _$this._sceneNumber;
  set sceneNumber(int? sceneNumber) => _$this._sceneNumber = sceneNumber;

  String? _scriptDay;
  String? get scriptDay => _$this._scriptDay;
  set scriptDay(String? scriptDay) => _$this._scriptDay = scriptDay;

  String? _summary;
  String? get summary => _$this._summary;
  set summary(String? summary) => _$this._summary = summary;

  DispoRowBuilder() {
    DispoRow._defaults(this);
  }

  DispoRowBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _location = $v.location;
      _mood = $v.mood;
      _plannedOrder = $v.plannedOrder;
      _sceneId = $v.sceneId;
      _sceneNumber = $v.sceneNumber;
      _scriptDay = $v.scriptDay;
      _summary = $v.summary;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DispoRow other) {
    _$v = other as _$DispoRow;
  }

  @override
  void update(void Function(DispoRowBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DispoRow build() => _build();

  _$DispoRow _build() {
    final _$result = _$v ??
        _$DispoRow._(
          location: location,
          mood: mood,
          plannedOrder: BuiltValueNullFieldError.checkNotNull(
              plannedOrder, r'DispoRow', 'plannedOrder'),
          sceneId: BuiltValueNullFieldError.checkNotNull(
              sceneId, r'DispoRow', 'sceneId'),
          sceneNumber: sceneNumber,
          scriptDay: scriptDay,
          summary: summary,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
