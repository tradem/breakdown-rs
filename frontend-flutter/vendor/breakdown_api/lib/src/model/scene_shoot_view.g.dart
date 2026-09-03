// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_shoot_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneShootView extends SceneShootView {
  @override
  final String? actualOrder;
  @override
  final BuiltList<String> continuityPhotoIds;
  @override
  final DateTime? endDt;
  @override
  final String id;
  @override
  final BuiltList<SerializedNote> notes;
  @override
  final String plannedOrder;
  @override
  final String sceneId;
  @override
  final String shootingDayId;
  @override
  final DateTime? startDt;
  @override
  final SceneShootStatus status;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$SceneShootView([void Function(SceneShootViewBuilder)? updates]) =>
      (SceneShootViewBuilder()..update(updates))._build();

  _$SceneShootView._(
      {this.actualOrder,
      required this.continuityPhotoIds,
      this.endDt,
      required this.id,
      required this.notes,
      required this.plannedOrder,
      required this.sceneId,
      required this.shootingDayId,
      this.startDt,
      required this.status,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  SceneShootView rebuild(void Function(SceneShootViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneShootViewBuilder toBuilder() => SceneShootViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneShootView &&
        actualOrder == other.actualOrder &&
        continuityPhotoIds == other.continuityPhotoIds &&
        endDt == other.endDt &&
        id == other.id &&
        notes == other.notes &&
        plannedOrder == other.plannedOrder &&
        sceneId == other.sceneId &&
        shootingDayId == other.shootingDayId &&
        startDt == other.startDt &&
        status == other.status &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, actualOrder.hashCode);
    _$hash = $jc(_$hash, continuityPhotoIds.hashCode);
    _$hash = $jc(_$hash, endDt.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, notes.hashCode);
    _$hash = $jc(_$hash, plannedOrder.hashCode);
    _$hash = $jc(_$hash, sceneId.hashCode);
    _$hash = $jc(_$hash, shootingDayId.hashCode);
    _$hash = $jc(_$hash, startDt.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneShootView')
          ..add('actualOrder', actualOrder)
          ..add('continuityPhotoIds', continuityPhotoIds)
          ..add('endDt', endDt)
          ..add('id', id)
          ..add('notes', notes)
          ..add('plannedOrder', plannedOrder)
          ..add('sceneId', sceneId)
          ..add('shootingDayId', shootingDayId)
          ..add('startDt', startDt)
          ..add('status', status)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class SceneShootViewBuilder
    implements Builder<SceneShootView, SceneShootViewBuilder> {
  _$SceneShootView? _$v;

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

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  ListBuilder<SerializedNote>? _notes;
  ListBuilder<SerializedNote> get notes =>
      _$this._notes ??= ListBuilder<SerializedNote>();
  set notes(ListBuilder<SerializedNote>? notes) => _$this._notes = notes;

  String? _plannedOrder;
  String? get plannedOrder => _$this._plannedOrder;
  set plannedOrder(String? plannedOrder) => _$this._plannedOrder = plannedOrder;

  String? _sceneId;
  String? get sceneId => _$this._sceneId;
  set sceneId(String? sceneId) => _$this._sceneId = sceneId;

  String? _shootingDayId;
  String? get shootingDayId => _$this._shootingDayId;
  set shootingDayId(String? shootingDayId) =>
      _$this._shootingDayId = shootingDayId;

  DateTime? _startDt;
  DateTime? get startDt => _$this._startDt;
  set startDt(DateTime? startDt) => _$this._startDt = startDt;

  SceneShootStatus? _status;
  SceneShootStatus? get status => _$this._status;
  set status(SceneShootStatus? status) => _$this._status = status;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SceneShootViewBuilder() {
    SceneShootView._defaults(this);
  }

  SceneShootViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _actualOrder = $v.actualOrder;
      _continuityPhotoIds = $v.continuityPhotoIds.toBuilder();
      _endDt = $v.endDt;
      _id = $v.id;
      _notes = $v.notes.toBuilder();
      _plannedOrder = $v.plannedOrder;
      _sceneId = $v.sceneId;
      _shootingDayId = $v.shootingDayId;
      _startDt = $v.startDt;
      _status = $v.status;
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneShootView other) {
    _$v = other as _$SceneShootView;
  }

  @override
  void update(void Function(SceneShootViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneShootView build() => _build();

  _$SceneShootView _build() {
    _$SceneShootView _$result;
    try {
      _$result = _$v ??
          _$SceneShootView._(
            actualOrder: actualOrder,
            continuityPhotoIds: continuityPhotoIds.build(),
            endDt: endDt,
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'SceneShootView', 'id'),
            notes: notes.build(),
            plannedOrder: BuiltValueNullFieldError.checkNotNull(
                plannedOrder, r'SceneShootView', 'plannedOrder'),
            sceneId: BuiltValueNullFieldError.checkNotNull(
                sceneId, r'SceneShootView', 'sceneId'),
            shootingDayId: BuiltValueNullFieldError.checkNotNull(
                shootingDayId, r'SceneShootView', 'shootingDayId'),
            startDt: startDt,
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'SceneShootView', 'status'),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'SceneShootView', 'updatedAt'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'SceneShootView', 'version'),
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
            r'SceneShootView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
