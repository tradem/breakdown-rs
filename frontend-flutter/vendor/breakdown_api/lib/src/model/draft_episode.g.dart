// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_episode.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftEpisode extends DraftEpisode {
  @override
  final int? number;
  @override
  final String? title;

  factory _$DraftEpisode([void Function(DraftEpisodeBuilder)? updates]) =>
      (DraftEpisodeBuilder()..update(updates))._build();

  _$DraftEpisode._({this.number, this.title}) : super._();
  @override
  DraftEpisode rebuild(void Function(DraftEpisodeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftEpisodeBuilder toBuilder() => DraftEpisodeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftEpisode &&
        number == other.number &&
        title == other.title;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, title.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftEpisode')
          ..add('number', number)
          ..add('title', title))
        .toString();
  }
}

class DraftEpisodeBuilder
    implements Builder<DraftEpisode, DraftEpisodeBuilder> {
  _$DraftEpisode? _$v;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  String? _title;
  String? get title => _$this._title;
  set title(String? title) => _$this._title = title;

  DraftEpisodeBuilder() {
    DraftEpisode._defaults(this);
  }

  DraftEpisodeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _number = $v.number;
      _title = $v.title;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftEpisode other) {
    _$v = other as _$DraftEpisode;
  }

  @override
  void update(void Function(DraftEpisodeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftEpisode build() => _build();

  _$DraftEpisode _build() {
    final _$result = _$v ??
        _$DraftEpisode._(
          number: number,
          title: title,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
