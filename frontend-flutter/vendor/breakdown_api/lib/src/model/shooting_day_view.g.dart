// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shooting_day_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ShootingDayView extends ShootingDayView {
  @override
  final bool archived;
  @override
  final Date? date;
  @override
  final String episodeId;
  @override
  final String id;
  @override
  final String? label;
  @override
  final String orderKey;
  @override
  final ShootingDaySource source_;
  @override
  final DateTime updatedAt;
  @override
  final int version;
  @override
  final DateTime? wrappedAt;

  factory _$ShootingDayView([void Function(ShootingDayViewBuilder)? updates]) =>
      (ShootingDayViewBuilder()..update(updates))._build();

  _$ShootingDayView._(
      {required this.archived,
      this.date,
      required this.episodeId,
      required this.id,
      this.label,
      required this.orderKey,
      required this.source_,
      required this.updatedAt,
      required this.version,
      this.wrappedAt})
      : super._();
  @override
  ShootingDayView rebuild(void Function(ShootingDayViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ShootingDayViewBuilder toBuilder() => ShootingDayViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ShootingDayView &&
        archived == other.archived &&
        date == other.date &&
        episodeId == other.episodeId &&
        id == other.id &&
        label == other.label &&
        orderKey == other.orderKey &&
        source_ == other.source_ &&
        updatedAt == other.updatedAt &&
        version == other.version &&
        wrappedAt == other.wrappedAt;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, archived.hashCode);
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, label.hashCode);
    _$hash = $jc(_$hash, orderKey.hashCode);
    _$hash = $jc(_$hash, source_.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jc(_$hash, wrappedAt.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ShootingDayView')
          ..add('archived', archived)
          ..add('date', date)
          ..add('episodeId', episodeId)
          ..add('id', id)
          ..add('label', label)
          ..add('orderKey', orderKey)
          ..add('source_', source_)
          ..add('updatedAt', updatedAt)
          ..add('version', version)
          ..add('wrappedAt', wrappedAt))
        .toString();
  }
}

class ShootingDayViewBuilder
    implements Builder<ShootingDayView, ShootingDayViewBuilder> {
  _$ShootingDayView? _$v;

  bool? _archived;
  bool? get archived => _$this._archived;
  set archived(bool? archived) => _$this._archived = archived;

  Date? _date;
  Date? get date => _$this._date;
  set date(Date? date) => _$this._date = date;

  String? _episodeId;
  String? get episodeId => _$this._episodeId;
  set episodeId(String? episodeId) => _$this._episodeId = episodeId;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _label;
  String? get label => _$this._label;
  set label(String? label) => _$this._label = label;

  String? _orderKey;
  String? get orderKey => _$this._orderKey;
  set orderKey(String? orderKey) => _$this._orderKey = orderKey;

  ShootingDaySourceBuilder? _source_;
  ShootingDaySourceBuilder get source_ =>
      _$this._source_ ??= ShootingDaySourceBuilder();
  set source_(ShootingDaySourceBuilder? source_) => _$this._source_ = source_;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  DateTime? _wrappedAt;
  DateTime? get wrappedAt => _$this._wrappedAt;
  set wrappedAt(DateTime? wrappedAt) => _$this._wrappedAt = wrappedAt;

  ShootingDayViewBuilder() {
    ShootingDayView._defaults(this);
  }

  ShootingDayViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _archived = $v.archived;
      _date = $v.date;
      _episodeId = $v.episodeId;
      _id = $v.id;
      _label = $v.label;
      _orderKey = $v.orderKey;
      _source_ = $v.source_.toBuilder();
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _wrappedAt = $v.wrappedAt;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ShootingDayView other) {
    _$v = other as _$ShootingDayView;
  }

  @override
  void update(void Function(ShootingDayViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ShootingDayView build() => _build();

  _$ShootingDayView _build() {
    _$ShootingDayView _$result;
    try {
      _$result = _$v ??
          _$ShootingDayView._(
            archived: BuiltValueNullFieldError.checkNotNull(
                archived, r'ShootingDayView', 'archived'),
            date: date,
            episodeId: BuiltValueNullFieldError.checkNotNull(
                episodeId, r'ShootingDayView', 'episodeId'),
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'ShootingDayView', 'id'),
            label: label,
            orderKey: BuiltValueNullFieldError.checkNotNull(
                orderKey, r'ShootingDayView', 'orderKey'),
            source_: source_.build(),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'ShootingDayView', 'updatedAt'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'ShootingDayView', 'version'),
            wrappedAt: wrappedAt,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'source_';
        source_.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ShootingDayView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
