// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'applied_episode.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppliedEpisode extends AppliedEpisode {
  @override
  final int appliedCount;
  @override
  final String id;
  @override
  final String? name;
  @override
  final int? number;

  factory _$AppliedEpisode([void Function(AppliedEpisodeBuilder)? updates]) =>
      (AppliedEpisodeBuilder()..update(updates))._build();

  _$AppliedEpisode._(
      {required this.appliedCount, required this.id, this.name, this.number})
      : super._();
  @override
  AppliedEpisode rebuild(void Function(AppliedEpisodeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppliedEpisodeBuilder toBuilder() => AppliedEpisodeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppliedEpisode &&
        appliedCount == other.appliedCount &&
        id == other.id &&
        name == other.name &&
        number == other.number;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, appliedCount.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AppliedEpisode')
          ..add('appliedCount', appliedCount)
          ..add('id', id)
          ..add('name', name)
          ..add('number', number))
        .toString();
  }
}

class AppliedEpisodeBuilder
    implements Builder<AppliedEpisode, AppliedEpisodeBuilder> {
  _$AppliedEpisode? _$v;

  int? _appliedCount;
  int? get appliedCount => _$this._appliedCount;
  set appliedCount(int? appliedCount) => _$this._appliedCount = appliedCount;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  AppliedEpisodeBuilder() {
    AppliedEpisode._defaults(this);
  }

  AppliedEpisodeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _appliedCount = $v.appliedCount;
      _id = $v.id;
      _name = $v.name;
      _number = $v.number;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AppliedEpisode other) {
    _$v = other as _$AppliedEpisode;
  }

  @override
  void update(void Function(AppliedEpisodeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppliedEpisode build() => _build();

  _$AppliedEpisode _build() {
    final _$result = _$v ??
        _$AppliedEpisode._(
          appliedCount: BuiltValueNullFieldError.checkNotNull(
              appliedCount, r'AppliedEpisode', 'appliedCount'),
          id: BuiltValueNullFieldError.checkNotNull(
              id, r'AppliedEpisode', 'id'),
          name: name,
          number: number,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
