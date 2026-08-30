// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EpisodeView extends EpisodeView {
  @override
  final String blockId;
  @override
  final String id;
  @override
  final String? name;
  @override
  final int number;
  @override
  final String seriesId;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$EpisodeView([void Function(EpisodeViewBuilder)? updates]) =>
      (EpisodeViewBuilder()..update(updates))._build();

  _$EpisodeView._(
      {required this.blockId,
      required this.id,
      this.name,
      required this.number,
      required this.seriesId,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  EpisodeView rebuild(void Function(EpisodeViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EpisodeViewBuilder toBuilder() => EpisodeViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EpisodeView &&
        blockId == other.blockId &&
        id == other.id &&
        name == other.name &&
        number == other.number &&
        seriesId == other.seriesId &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, seriesId.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EpisodeView')
          ..add('blockId', blockId)
          ..add('id', id)
          ..add('name', name)
          ..add('number', number)
          ..add('seriesId', seriesId)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class EpisodeViewBuilder implements Builder<EpisodeView, EpisodeViewBuilder> {
  _$EpisodeView? _$v;

  String? _blockId;
  String? get blockId => _$this._blockId;
  set blockId(String? blockId) => _$this._blockId = blockId;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  String? _seriesId;
  String? get seriesId => _$this._seriesId;
  set seriesId(String? seriesId) => _$this._seriesId = seriesId;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  EpisodeViewBuilder() {
    EpisodeView._defaults(this);
  }

  EpisodeViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _blockId = $v.blockId;
      _id = $v.id;
      _name = $v.name;
      _number = $v.number;
      _seriesId = $v.seriesId;
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EpisodeView other) {
    _$v = other as _$EpisodeView;
  }

  @override
  void update(void Function(EpisodeViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EpisodeView build() => _build();

  _$EpisodeView _build() {
    final _$result = _$v ??
        _$EpisodeView._(
          blockId: BuiltValueNullFieldError.checkNotNull(
              blockId, r'EpisodeView', 'blockId'),
          id: BuiltValueNullFieldError.checkNotNull(id, r'EpisodeView', 'id'),
          name: name,
          number: BuiltValueNullFieldError.checkNotNull(
              number, r'EpisodeView', 'number'),
          seriesId: BuiltValueNullFieldError.checkNotNull(
              seriesId, r'EpisodeView', 'seriesId'),
          updatedAt: BuiltValueNullFieldError.checkNotNull(
              updatedAt, r'EpisodeView', 'updatedAt'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'EpisodeView', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
