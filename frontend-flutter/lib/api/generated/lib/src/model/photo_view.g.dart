// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoView extends PhotoView {
  @override
  final PhotoBinding binding;
  @override
  final String contentType;
  @override
  final DateTime? exifStrippedAt;
  @override
  final String id;
  @override
  final int sizeBytes;
  @override
  final BuiltList<PhotoVariantView> variants;
  @override
  final int version;

  factory _$PhotoView([void Function(PhotoViewBuilder)? updates]) =>
      (PhotoViewBuilder()..update(updates))._build();

  _$PhotoView._(
      {required this.binding,
      required this.contentType,
      this.exifStrippedAt,
      required this.id,
      required this.sizeBytes,
      required this.variants,
      required this.version})
      : super._();
  @override
  PhotoView rebuild(void Function(PhotoViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoViewBuilder toBuilder() => PhotoViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoView &&
        binding == other.binding &&
        contentType == other.contentType &&
        exifStrippedAt == other.exifStrippedAt &&
        id == other.id &&
        sizeBytes == other.sizeBytes &&
        variants == other.variants &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, binding.hashCode);
    _$hash = $jc(_$hash, contentType.hashCode);
    _$hash = $jc(_$hash, exifStrippedAt.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, variants.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoView')
          ..add('binding', binding)
          ..add('contentType', contentType)
          ..add('exifStrippedAt', exifStrippedAt)
          ..add('id', id)
          ..add('sizeBytes', sizeBytes)
          ..add('variants', variants)
          ..add('version', version))
        .toString();
  }
}

class PhotoViewBuilder implements Builder<PhotoView, PhotoViewBuilder> {
  _$PhotoView? _$v;

  PhotoBindingBuilder? _binding;
  PhotoBindingBuilder get binding => _$this._binding ??= PhotoBindingBuilder();
  set binding(PhotoBindingBuilder? binding) => _$this._binding = binding;

  String? _contentType;
  String? get contentType => _$this._contentType;
  set contentType(String? contentType) => _$this._contentType = contentType;

  DateTime? _exifStrippedAt;
  DateTime? get exifStrippedAt => _$this._exifStrippedAt;
  set exifStrippedAt(DateTime? exifStrippedAt) =>
      _$this._exifStrippedAt = exifStrippedAt;

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

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  PhotoViewBuilder() {
    PhotoView._defaults(this);
  }

  PhotoViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _binding = $v.binding.toBuilder();
      _contentType = $v.contentType;
      _exifStrippedAt = $v.exifStrippedAt;
      _id = $v.id;
      _sizeBytes = $v.sizeBytes;
      _variants = $v.variants.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoView other) {
    _$v = other as _$PhotoView;
  }

  @override
  void update(void Function(PhotoViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoView build() => _build();

  _$PhotoView _build() {
    _$PhotoView _$result;
    try {
      _$result = _$v ??
          _$PhotoView._(
            binding: binding.build(),
            contentType: BuiltValueNullFieldError.checkNotNull(
                contentType, r'PhotoView', 'contentType'),
            exifStrippedAt: exifStrippedAt,
            id: BuiltValueNullFieldError.checkNotNull(id, r'PhotoView', 'id'),
            sizeBytes: BuiltValueNullFieldError.checkNotNull(
                sizeBytes, r'PhotoView', 'sizeBytes'),
            variants: variants.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'PhotoView', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'binding';
        binding.build();

        _$failedField = 'variants';
        variants.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'PhotoView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
