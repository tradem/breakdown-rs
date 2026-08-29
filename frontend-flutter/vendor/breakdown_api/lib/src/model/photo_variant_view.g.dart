// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'photo_variant_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$PhotoVariantView extends PhotoVariantView {
  @override
  final PhotoVariant kind;
  @override
  final int sizeBytes;
  @override
  final VariantStatus status;

  factory _$PhotoVariantView(
          [void Function(PhotoVariantViewBuilder)? updates]) =>
      (PhotoVariantViewBuilder()..update(updates))._build();

  _$PhotoVariantView._(
      {required this.kind, required this.sizeBytes, required this.status})
      : super._();
  @override
  PhotoVariantView rebuild(void Function(PhotoVariantViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  PhotoVariantViewBuilder toBuilder() =>
      PhotoVariantViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is PhotoVariantView &&
        kind == other.kind &&
        sizeBytes == other.sizeBytes &&
        status == other.status;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, sizeBytes.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'PhotoVariantView')
          ..add('kind', kind)
          ..add('sizeBytes', sizeBytes)
          ..add('status', status))
        .toString();
  }
}

class PhotoVariantViewBuilder
    implements Builder<PhotoVariantView, PhotoVariantViewBuilder> {
  _$PhotoVariantView? _$v;

  PhotoVariant? _kind;
  PhotoVariant? get kind => _$this._kind;
  set kind(PhotoVariant? kind) => _$this._kind = kind;

  int? _sizeBytes;
  int? get sizeBytes => _$this._sizeBytes;
  set sizeBytes(int? sizeBytes) => _$this._sizeBytes = sizeBytes;

  VariantStatus? _status;
  VariantStatus? get status => _$this._status;
  set status(VariantStatus? status) => _$this._status = status;

  PhotoVariantViewBuilder() {
    PhotoVariantView._defaults(this);
  }

  PhotoVariantViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _sizeBytes = $v.sizeBytes;
      _status = $v.status;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(PhotoVariantView other) {
    _$v = other as _$PhotoVariantView;
  }

  @override
  void update(void Function(PhotoVariantViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  PhotoVariantView build() => _build();

  _$PhotoVariantView _build() {
    final _$result = _$v ??
        _$PhotoVariantView._(
          kind: BuiltValueNullFieldError.checkNotNull(
              kind, r'PhotoVariantView', 'kind'),
          sizeBytes: BuiltValueNullFieldError.checkNotNull(
              sizeBytes, r'PhotoVariantView', 'sizeBytes'),
          status: BuiltValueNullFieldError.checkNotNull(
              status, r'PhotoVariantView', 'status'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
