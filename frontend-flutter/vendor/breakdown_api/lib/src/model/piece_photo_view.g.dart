// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'piece_photo_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PiecePhotoView extends PiecePhotoView {
  @override
  final String contentType;
  @override
  final String id;
  @override
  final int sizeBytes;
  @override
  final BuiltList<PhotoVariantView> variants;

  factory _$PiecePhotoView([void Function(PiecePhotoViewBuilder)? updates]) =>
      (PiecePhotoViewBuilder()..update(updates))._build();

  _$PiecePhotoView._(
      {required this.contentType,
      required this.id,
      required this.sizeBytes,
      required this.variants})
      : super._();
  @override
  PiecePhotoView rebuild(void Function(PiecePhotoViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PiecePhotoViewBuilder toBuilder() => PiecePhotoViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PiecePhotoView &&
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
    return (newBuiltValueToStringHelper(r'PiecePhotoView')
          ..add('contentType', contentType)
          ..add('id', id)
          ..add('sizeBytes', sizeBytes)
          ..add('variants', variants))
        .toString();
  }
}

class PiecePhotoViewBuilder
    implements Builder<PiecePhotoView, PiecePhotoViewBuilder> {
  _$PiecePhotoView? _$v;

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

  PiecePhotoViewBuilder() {
    PiecePhotoView._defaults(this);
  }

  PiecePhotoViewBuilder get _$this {
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
  void replace(PiecePhotoView other) {
    _$v = other as _$PiecePhotoView;
  }

  @override
  void update(void Function(PiecePhotoViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PiecePhotoView build() => _build();

  _$PiecePhotoView _build() {
    _$PiecePhotoView _$result;
    try {
      _$result = _$v ??
          _$PiecePhotoView._(
            contentType: BuiltValueNullFieldError.checkNotNull(
                contentType, r'PiecePhotoView', 'contentType'),
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'PiecePhotoView', 'id'),
            sizeBytes: BuiltValueNullFieldError.checkNotNull(
                sizeBytes, r'PiecePhotoView', 'sizeBytes'),
            variants: variants.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'variants';
        variants.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PiecePhotoView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
