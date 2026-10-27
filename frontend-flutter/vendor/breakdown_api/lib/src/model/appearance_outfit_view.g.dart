// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'appearance_outfit_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AppearanceOutfitView extends AppearanceOutfitView {
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

  factory _$AppearanceOutfitView(
          [void Function(AppearanceOutfitViewBuilder)? updates]) =>
      (AppearanceOutfitViewBuilder()..update(updates))._build();

  _$AppearanceOutfitView._(
      {this.note,
      required this.order,
      required this.outfitId,
      this.outfitName,
      this.variantOf})
      : super._();
  @override
  AppearanceOutfitView rebuild(
          void Function(AppearanceOutfitViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AppearanceOutfitViewBuilder toBuilder() =>
      AppearanceOutfitViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AppearanceOutfitView &&
        note == other.note &&
        order == other.order &&
        outfitId == other.outfitId &&
        outfitName == other.outfitName &&
        variantOf == other.variantOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
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
    return (newBuiltValueToStringHelper(r'AppearanceOutfitView')
          ..add('note', note)
          ..add('order', order)
          ..add('outfitId', outfitId)
          ..add('outfitName', outfitName)
          ..add('variantOf', variantOf))
        .toString();
  }
}

class AppearanceOutfitViewBuilder
    implements Builder<AppearanceOutfitView, AppearanceOutfitViewBuilder> {
  _$AppearanceOutfitView? _$v;

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

  AppearanceOutfitViewBuilder() {
    AppearanceOutfitView._defaults(this);
  }

  AppearanceOutfitViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
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
  void replace(AppearanceOutfitView other) {
    _$v = other as _$AppearanceOutfitView;
  }

  @override
  void update(void Function(AppearanceOutfitViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AppearanceOutfitView build() => _build();

  _$AppearanceOutfitView _build() {
    final _$result = _$v ??
        _$AppearanceOutfitView._(
          note: note,
          order: BuiltValueNullFieldError.checkNotNull(
              order, r'AppearanceOutfitView', 'order'),
          outfitId: BuiltValueNullFieldError.checkNotNull(
              outfitId, r'AppearanceOutfitView', 'outfitId'),
          outfitName: outfitName,
          variantOf: variantOf,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
