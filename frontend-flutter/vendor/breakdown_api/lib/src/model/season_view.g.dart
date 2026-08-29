// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SeasonView extends SeasonView {
  @override
  final String id;
  @override
  final int number;
  @override
  final String seriesId;
  @override
  final String? title;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$SeasonView([void Function(SeasonViewBuilder)? updates]) =>
      (SeasonViewBuilder()..update(updates))._build();

  _$SeasonView._(
      {required this.id,
      required this.number,
      required this.seriesId,
      this.title,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  SeasonView rebuild(void Function(SeasonViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SeasonViewBuilder toBuilder() => SeasonViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SeasonView &&
        id == other.id &&
        number == other.number &&
        seriesId == other.seriesId &&
        title == other.title &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, seriesId.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SeasonView')
          ..add('id', id)
          ..add('number', number)
          ..add('seriesId', seriesId)
          ..add('title', title)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class SeasonViewBuilder implements Builder<SeasonView, SeasonViewBuilder> {
  _$SeasonView? _$v;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  String? _seriesId;
  String? get seriesId => _$this._seriesId;
  set seriesId(String? seriesId) => _$this._seriesId = seriesId;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  SeasonViewBuilder() {
    SeasonView._defaults(this);
  }

  SeasonViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _id = $v.id;
      _number = $v.number;
      _seriesId = $v.seriesId;
      _title = $v.title;
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SeasonView other) {
    _$v = other as _$SeasonView;
  }

  @override
  void update(void Function(SeasonViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SeasonView build() => _build();

  _$SeasonView _build() {
    final _$result = _$v ??
        _$SeasonView._(
          id: BuiltValueNullFieldError.checkNotNull(id, r'SeasonView', 'id'),
          number: BuiltValueNullFieldError.checkNotNull(
              number, r'SeasonView', 'number'),
          seriesId: BuiltValueNullFieldError.checkNotNull(
              seriesId, r'SeasonView', 'seriesId'),
          title: title,
          updatedAt: BuiltValueNullFieldError.checkNotNull(
              updatedAt, r'SeasonView', 'updatedAt'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'SeasonView', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
