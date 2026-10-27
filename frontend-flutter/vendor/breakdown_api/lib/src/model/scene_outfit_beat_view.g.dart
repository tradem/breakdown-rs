// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_outfit_beat_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneOutfitBeatView extends SceneOutfitBeatView {
  @override
  final String characterId;
  @override
  final String? characterName;
  @override
  final String? note;
  @override
  final int order;
  @override
  final String outfitId;
  @override
  final String? outfitName;
  @override
  final String? variantOf;

  factory _$SceneOutfitBeatView(
          [void Function(SceneOutfitBeatViewBuilder)? updates]) =>
      (SceneOutfitBeatViewBuilder()..update(updates))._build();

  _$SceneOutfitBeatView._(
      {required this.characterId,
      this.characterName,
      this.note,
      required this.order,
      required this.outfitId,
      this.outfitName,
      this.variantOf})
      : super._();
  @override
  SceneOutfitBeatView rebuild(
          void Function(SceneOutfitBeatViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneOutfitBeatViewBuilder toBuilder() =>
      SceneOutfitBeatViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneOutfitBeatView &&
        characterId == other.characterId &&
        characterName == other.characterName &&
        note == other.note &&
        order == other.order &&
        outfitId == other.outfitId &&
        outfitName == other.outfitName &&
        variantOf == other.variantOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, order.hashCode);
    _$hash = $jc(_$hash, outfitId.hashCode);
    _$hash = $jc(_$hash, outfitName.hashCode);
    _$hash = $jc(_$hash, variantOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneOutfitBeatView')
          ..add('characterId', characterId)
          ..add('characterName', characterName)
          ..add('note', note)
          ..add('order', order)
          ..add('outfitId', outfitId)
          ..add('outfitName', outfitName)
          ..add('variantOf', variantOf))
        .toString();
  }
}

class SceneOutfitBeatViewBuilder
    implements Builder<SceneOutfitBeatView, SceneOutfitBeatViewBuilder> {
  _$SceneOutfitBeatView? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  int? _order;
  int? get order => _$this._order;
  set order(int? order) => _$this._order = order;

  String? _outfitId;
  String? get outfitId => _$this._outfitId;
  set outfitId(String? outfitId) => _$this._outfitId = outfitId;

  String? _outfitName;
  String? get outfitName => _$this._outfitName;
  set outfitName(String? outfitName) => _$this._outfitName = outfitName;

  String? _variantOf;
  String? get variantOf => _$this._variantOf;
  set variantOf(String? variantOf) => _$this._variantOf = variantOf;

  SceneOutfitBeatViewBuilder() {
    SceneOutfitBeatView._defaults(this);
  }

  SceneOutfitBeatViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _characterName = $v.characterName;
      _note = $v.note;
      _order = $v.order;
      _outfitId = $v.outfitId;
      _outfitName = $v.outfitName;
      _variantOf = $v.variantOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneOutfitBeatView other) {
    _$v = other as _$SceneOutfitBeatView;
  }

  @override
  void update(void Function(SceneOutfitBeatViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneOutfitBeatView build() => _build();

  _$SceneOutfitBeatView _build() {
    final _$result = _$v ??
        _$SceneOutfitBeatView._(
          characterId: BuiltValueNullFieldError.checkNotNull(
              characterId, r'SceneOutfitBeatView', 'characterId'),
          characterName: characterName,
          note: note,
          order: BuiltValueNullFieldError.checkNotNull(
              order, r'SceneOutfitBeatView', 'order'),
          outfitId: BuiltValueNullFieldError.checkNotNull(
              outfitId, r'SceneOutfitBeatView', 'outfitId'),
          outfitName: outfitName,
          variantOf: variantOf,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
