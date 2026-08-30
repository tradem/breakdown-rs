// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_category_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostumeCategoryView extends CostumeCategoryView {
  @override
  final bool archived;
  @override
  final String id;
  @override
  final String name;
  @override
  final String orderKey;
  @override
  final String seasonId;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$CostumeCategoryView(
          [void Function(CostumeCategoryViewBuilder)? updates]) =>
      (CostumeCategoryViewBuilder()..update(updates))._build();

  _$CostumeCategoryView._(
      {required this.archived,
      required this.id,
      required this.name,
      required this.orderKey,
      required this.seasonId,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  CostumeCategoryView rebuild(
          void Function(CostumeCategoryViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostumeCategoryViewBuilder toBuilder() =>
      CostumeCategoryViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostumeCategoryView &&
        archived == other.archived &&
        id == other.id &&
        name == other.name &&
        orderKey == other.orderKey &&
        seasonId == other.seasonId &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, archived.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, orderKey.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostumeCategoryView')
          ..add('archived', archived)
          ..add('id', id)
          ..add('name', name)
          ..add('orderKey', orderKey)
          ..add('seasonId', seasonId)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class CostumeCategoryViewBuilder
    implements Builder<CostumeCategoryView, CostumeCategoryViewBuilder> {
  _$CostumeCategoryView? _$v;

  bool? _archived;
  bool? get archived => _$this._archived;
  set archived(bool? archived) => _$this._archived = archived;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _orderKey;
  String? get orderKey => _$this._orderKey;
  set orderKey(String? orderKey) => _$this._orderKey = orderKey;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  CostumeCategoryViewBuilder() {
    CostumeCategoryView._defaults(this);
  }

  CostumeCategoryViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _archived = $v.archived;
      _id = $v.id;
      _name = $v.name;
      _orderKey = $v.orderKey;
      _seasonId = $v.seasonId;
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostumeCategoryView other) {
    _$v = other as _$CostumeCategoryView;
  }

  @override
  void update(void Function(CostumeCategoryViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostumeCategoryView build() => _build();

  _$CostumeCategoryView _build() {
    final _$result = _$v ??
        _$CostumeCategoryView._(
          archived: BuiltValueNullFieldError.checkNotNull(
              archived, r'CostumeCategoryView', 'archived'),
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'CostumeCategoryView', 'id'),
          name: BuiltValueNullFieldError.checkNotNull(
              name, r'CostumeCategoryView', 'name'),
          orderKey: BuiltValueNullFieldError.checkNotNull(
              orderKey, r'CostumeCategoryView', 'orderKey'),
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'CostumeCategoryView', 'seasonId'),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
              updatedAt, r'CostumeCategoryView', 'updatedAt'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'CostumeCategoryView', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
