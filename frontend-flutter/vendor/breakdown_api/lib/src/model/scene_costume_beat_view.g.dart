// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_costume_beat_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SceneCostumeBeatView extends SceneCostumeBeatView {
  @override
  final String characterId;
  @override
  final String? characterName;
  @override
  final String? costumeCategoryId;
  @override
  final String? costumeCategoryName;
  @override
  final String costumeId;
  @override
  final String? note;
  @override
  final int order;

  factory _$SceneCostumeBeatView(
          [void Function(SceneCostumeBeatViewBuilder)? updates]) =>
      (SceneCostumeBeatViewBuilder()..update(updates))._build();

  _$SceneCostumeBeatView._(
      {required this.characterId,
      this.characterName,
      this.costumeCategoryId,
      this.costumeCategoryName,
      required this.costumeId,
      this.note,
      required this.order})
      : super._();
  @override
  SceneCostumeBeatView rebuild(
          void Function(SceneCostumeBeatViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SceneCostumeBeatViewBuilder toBuilder() =>
      SceneCostumeBeatViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SceneCostumeBeatView &&
        characterId == other.characterId &&
        characterName == other.characterName &&
        costumeCategoryId == other.costumeCategoryId &&
        costumeCategoryName == other.costumeCategoryName &&
        costumeId == other.costumeId &&
        note == other.note &&
        order == other.order;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterId.hashCode);
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, costumeCategoryId.hashCode);
    _$hash = $jc(_$hash, costumeCategoryName.hashCode);
    _$hash = $jc(_$hash, costumeId.hashCode);
    _$hash = $jc(_$hash, note.hashCode);
    _$hash = $jc(_$hash, order.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SceneCostumeBeatView')
          ..add('characterId', characterId)
          ..add('characterName', characterName)
          ..add('costumeCategoryId', costumeCategoryId)
          ..add('costumeCategoryName', costumeCategoryName)
          ..add('costumeId', costumeId)
          ..add('note', note)
          ..add('order', order))
        .toString();
  }
}

class SceneCostumeBeatViewBuilder
    implements Builder<SceneCostumeBeatView, SceneCostumeBeatViewBuilder> {
  _$SceneCostumeBeatView? _$v;

  String? _characterId;
  String? get characterId => _$this._characterId;
  set characterId(String? characterId) => _$this._characterId = characterId;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _costumeCategoryId;
  String? get costumeCategoryId => _$this._costumeCategoryId;
  set costumeCategoryId(String? costumeCategoryId) =>
      _$this._costumeCategoryId = costumeCategoryId;

  String? _costumeCategoryName;
  String? get costumeCategoryName => _$this._costumeCategoryName;
  set costumeCategoryName(String? costumeCategoryName) =>
      _$this._costumeCategoryName = costumeCategoryName;

  String? _costumeId;
  String? get costumeId => _$this._costumeId;
  set costumeId(String? costumeId) => _$this._costumeId = costumeId;

  String? _note;
  String? get note => _$this._note;
  set note(String? note) => _$this._note = note;

  int? _order;
  int? get order => _$this._order;
  set order(int? order) => _$this._order = order;

  SceneCostumeBeatViewBuilder() {
    SceneCostumeBeatView._defaults(this);
  }

  SceneCostumeBeatViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterId = $v.characterId;
      _characterName = $v.characterName;
      _costumeCategoryId = $v.costumeCategoryId;
      _costumeCategoryName = $v.costumeCategoryName;
      _costumeId = $v.costumeId;
      _note = $v.note;
      _order = $v.order;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SceneCostumeBeatView other) {
    _$v = other as _$SceneCostumeBeatView;
  }

  @override
  void update(void Function(SceneCostumeBeatViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SceneCostumeBeatView build() => _build();

  _$SceneCostumeBeatView _build() {
    final _$result = _$v ??
        _$SceneCostumeBeatView._(
          characterId: BuiltValueNullFieldError.checkNotNull(
              characterId, r'SceneCostumeBeatView', 'characterId'),
          characterName: characterName,
          costumeCategoryId: costumeCategoryId,
          costumeCategoryName: costumeCategoryName,
          costumeId: BuiltValueNullFieldError.checkNotNull(
              costumeId, r'SceneCostumeBeatView', 'costumeId'),
          note: note,
          order: BuiltValueNullFieldError.checkNotNull(
              order, r'SceneCostumeBeatView', 'order'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
