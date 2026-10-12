// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_costume_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppearanceCostumeView extends AppearanceCostumeView {
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

  factory _$AppearanceCostumeView(
          [void Function(AppearanceCostumeViewBuilder)? updates]) =>
      (AppearanceCostumeViewBuilder()..update(updates))._build();

  _$AppearanceCostumeView._(
      {this.costumeCategoryId,
      this.costumeCategoryName,
      required this.costumeId,
      this.note,
      required this.order})
      : super._();
  @override
  AppearanceCostumeView rebuild(
          void Function(AppearanceCostumeViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppearanceCostumeViewBuilder toBuilder() =>
      AppearanceCostumeViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppearanceCostumeView &&
        costumeCategoryId == other.costumeCategoryId &&
        costumeCategoryName == other.costumeCategoryName &&
        costumeId == other.costumeId &&
        note == other.note &&
        order == other.order;
  }

  @override
  int get hashCode {
    var _$hash = 0;
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
    return (newBuiltValueToStringHelper(r'AppearanceCostumeView')
          ..add('costumeCategoryId', costumeCategoryId)
          ..add('costumeCategoryName', costumeCategoryName)
          ..add('costumeId', costumeId)
          ..add('note', note)
          ..add('order', order))
        .toString();
  }
}

class AppearanceCostumeViewBuilder
    implements Builder<AppearanceCostumeView, AppearanceCostumeViewBuilder> {
  _$AppearanceCostumeView? _$v;

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

  AppearanceCostumeViewBuilder() {
    AppearanceCostumeView._defaults(this);
  }

  AppearanceCostumeViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
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
  void replace(AppearanceCostumeView other) {
    _$v = other as _$AppearanceCostumeView;
  }

  @override
  void update(void Function(AppearanceCostumeViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppearanceCostumeView build() => _build();

  _$AppearanceCostumeView _build() {
    final _$result = _$v ??
        _$AppearanceCostumeView._(
          costumeCategoryId: costumeCategoryId,
          costumeCategoryName: costumeCategoryName,
          costumeId: BuiltValueNullFieldError.checkNotNull(
              costumeId, r'AppearanceCostumeView', 'costumeId'),
          note: note,
          order: BuiltValueNullFieldError.checkNotNull(
              order, r'AppearanceCostumeView', 'order'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
