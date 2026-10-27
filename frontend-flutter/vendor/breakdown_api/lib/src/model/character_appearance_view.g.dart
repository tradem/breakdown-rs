// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'character_appearance_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CharacterAppearanceView extends CharacterAppearanceView {
  @override
  final String episodeId;
  @override
  final BuiltList<AppearanceOutfitView>? outfits;
  @override
  final String sceneId;
  @override
  final int? sceneNumber;
  @override
  final String? synopsis;

  factory _$CharacterAppearanceView(
          [void Function(CharacterAppearanceViewBuilder)? updates]) =>
      (CharacterAppearanceViewBuilder()..update(updates))._build();

  _$CharacterAppearanceView._(
      {required this.episodeId,
      this.outfits,
      required this.sceneId,
      this.sceneNumber,
      this.synopsis})
      : super._();
  @override
  CharacterAppearanceView rebuild(
          void Function(CharacterAppearanceViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CharacterAppearanceViewBuilder toBuilder() =>
      CharacterAppearanceViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CharacterAppearanceView &&
        episodeId == other.episodeId &&
        outfits == other.outfits &&
        sceneId == other.sceneId &&
        sceneNumber == other.sceneNumber &&
        synopsis == other.synopsis;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jc(_$hash, outfits.hashCode);
    _$hash = $jc(_$hash, sceneId.hashCode);
    _$hash = $jc(_$hash, sceneNumber.hashCode);
    _$hash = $jc(_$hash, synopsis.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CharacterAppearanceView')
          ..add('episodeId', episodeId)
          ..add('outfits', outfits)
          ..add('sceneId', sceneId)
          ..add('sceneNumber', sceneNumber)
          ..add('synopsis', synopsis))
        .toString();
  }
}

class CharacterAppearanceViewBuilder
    implements
        Builder<CharacterAppearanceView, CharacterAppearanceViewBuilder> {
  _$CharacterAppearanceView? _$v;

  String? _episodeId;
  String? get episodeId => _$this._episodeId;
  set episodeId(String? episodeId) => _$this._episodeId = episodeId;

  ListBuilder<AppearanceOutfitView>? _outfits;
  ListBuilder<AppearanceOutfitView> get outfits =>
      _$this._outfits ??= ListBuilder<AppearanceOutfitView>();
  set outfits(ListBuilder<AppearanceOutfitView>? outfits) =>
      _$this._outfits = outfits;

  String? _sceneId;
  String? get sceneId => _$this._sceneId;
  set sceneId(String? sceneId) => _$this._sceneId = sceneId;

  int? _sceneNumber;
  int? get sceneNumber => _$this._sceneNumber;
  set sceneNumber(int? sceneNumber) => _$this._sceneNumber = sceneNumber;

  String? _synopsis;
  String? get synopsis => _$this._synopsis;
  set synopsis(String? synopsis) => _$this._synopsis = synopsis;

  CharacterAppearanceViewBuilder() {
    CharacterAppearanceView._defaults(this);
  }

  CharacterAppearanceViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _episodeId = $v.episodeId;
      _outfits = $v.outfits?.toBuilder();
      _sceneId = $v.sceneId;
      _sceneNumber = $v.sceneNumber;
      _synopsis = $v.synopsis;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CharacterAppearanceView other) {
    _$v = other as _$CharacterAppearanceView;
  }

  @override
  void update(void Function(CharacterAppearanceViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CharacterAppearanceView build() => _build();

  _$CharacterAppearanceView _build() {
    _$CharacterAppearanceView _$result;
    try {
      _$result = _$v ??
          _$CharacterAppearanceView._(
            episodeId: BuiltValueNullFieldError.checkNotNull(
                episodeId, r'CharacterAppearanceView', 'episodeId'),
            outfits: _outfits?.build(),
            sceneId: BuiltValueNullFieldError.checkNotNull(
                sceneId, r'CharacterAppearanceView', 'sceneId'),
            sceneNumber: sceneNumber,
            synopsis: synopsis,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'outfits';
        _outfits?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CharacterAppearanceView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
