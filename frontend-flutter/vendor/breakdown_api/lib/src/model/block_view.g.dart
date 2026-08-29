// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'block_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BlockView extends BlockView {
  @override
  final String endDate;
  @override
  final String id;
  @override
  final int number;
  @override
  final String seasonId;
  @override
  final String seriesId;
  @override
  final String startDate;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$BlockView([void Function(BlockViewBuilder)? updates]) =>
      (BlockViewBuilder()..update(updates))._build();

  _$BlockView._(
      {required this.endDate,
      required this.id,
      required this.number,
      required this.seasonId,
      required this.seriesId,
      required this.startDate,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  BlockView rebuild(void Function(BlockViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BlockViewBuilder toBuilder() => BlockViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BlockView &&
        endDate == other.endDate &&
        id == other.id &&
        number == other.number &&
        seasonId == other.seasonId &&
        seriesId == other.seriesId &&
        startDate == other.startDate &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, endDate.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jc(_$hash, seriesId.hashCode);
    _$hash = $jc(_$hash, startDate.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BlockView')
          ..add('endDate', endDate)
          ..add('id', id)
          ..add('number', number)
          ..add('seasonId', seasonId)
          ..add('seriesId', seriesId)
          ..add('startDate', startDate)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class BlockViewBuilder implements Builder<BlockView, BlockViewBuilder> {
  _$BlockView? _$v;

  String? _endDate;
  String? get endDate => _$this._endDate;
  set endDate(String? endDate) => _$this._endDate = endDate;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  String? _seriesId;
  String? get seriesId => _$this._seriesId;
  set seriesId(String? seriesId) => _$this._seriesId = seriesId;

  String? _startDate;
  String? get startDate => _$this._startDate;
  set startDate(String? startDate) => _$this._startDate = startDate;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  BlockViewBuilder() {
    BlockView._defaults(this);
  }

  BlockViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _endDate = $v.endDate;
      _id = $v.id;
      _number = $v.number;
      _seasonId = $v.seasonId;
      _seriesId = $v.seriesId;
      _startDate = $v.startDate;
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BlockView other) {
    _$v = other as _$BlockView;
  }

  @override
  void update(void Function(BlockViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BlockView build() => _build();

  _$BlockView _build() {
    final _$result = _$v ??
        _$BlockView._(
          endDate: BuiltValueNullFieldError.checkNotNull(
              endDate, r'BlockView', 'endDate'),
          id: BuiltValueNullFieldError.checkNotNull(id, r'BlockView', 'id'),
          number: BuiltValueNullFieldError.checkNotNull(
              number, r'BlockView', 'number'),
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'BlockView', 'seasonId'),
          seriesId: BuiltValueNullFieldError.checkNotNull(
              seriesId, r'BlockView', 'seriesId'),
          startDate: BuiltValueNullFieldError.checkNotNull(
              startDate, r'BlockView', 'startDate'),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
              updatedAt, r'BlockView', 'updatedAt'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'BlockView', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
