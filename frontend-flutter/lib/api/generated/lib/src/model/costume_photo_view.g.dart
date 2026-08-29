// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'costume_photo_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CostumePhotoView extends CostumePhotoView {
  @override
  final String contentType;
  @override
  final String id;
  @override
  final int sizeBytes;
  @override
  final BuiltList<PhotoVariantView> variants;

  factory _$CostumePhotoView(
          [void Function(CostumePhotoViewBuilder)? updates]) =>
      (CostumePhotoViewBuilder()..update(updates))._build();

  _$CostumePhotoView._(
      {required this.contentType,
      required this.id,
      required this.sizeBytes,
      required this.variants})
      : super._();
  @override
  CostumePhotoView rebuild(void Function(CostumePhotoViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CostumePhotoViewBuilder toBuilder() =>
      CostumePhotoViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CostumePhotoView &&
        contentType == other.contentType &&
        id == other.id &&
        sizeBytes == other.sizeBytes &&
        variants == other.variants;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, contentType.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, variants.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CostumePhotoView')
          ..add('contentType', contentType)
          ..add('id', id)
          ..add('sizeBytes', sizeBytes)
          ..add('variants', variants))
        .toString();
  }
}

class CostumePhotoViewBuilder
    implements Builder<CostumePhotoView, CostumePhotoViewBuilder> {
  _$CostumePhotoView? _$v;

  String? _contentType;
  String? get contentType => _$this._contentType;
  set contentType(String? contentType) => _$this._contentType = contentType;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  ListBuilder<PhotoVariantView>? _variants;
  ListBuilder<PhotoVariantView> get variants =>
      _$this._variants ??= ListBuilder<PhotoVariantView>();
  set variants(ListBuilder<PhotoVariantView>? variants) =>
      _$this._variants = variants;

  CostumePhotoViewBuilder() {
    CostumePhotoView._defaults(this);
  }

  CostumePhotoViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _contentType = $v.contentType;
      _id = $v.id;
      _sizeBytes = $v.sizeBytes;
      _variants = $v.variants.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CostumePhotoView other) {
    _$v = other as _$CostumePhotoView;
  }

  @override
  void update(void Function(CostumePhotoViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CostumePhotoView build() => _build();

  _$CostumePhotoView _build() {
    _$CostumePhotoView _$result;
    try {
      _$result = _$v ??
          _$CostumePhotoView._(
            contentType: BuiltValueNullFieldError.checkNotNull(
                contentType, r'CostumePhotoView', 'contentType'),
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'CostumePhotoView', 'id'),
            sizeBytes: BuiltValueNullFieldError.checkNotNull(
                sizeBytes, r'CostumePhotoView', 'sizeBytes'),
            variants: variants.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'variants';
        variants.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CostumePhotoView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
