// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_continuity_photo_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LinkContinuityPhotoRequest extends LinkContinuityPhotoRequest {
  @override
  final String photoId;
  @override
  final int version;

  factory _$LinkContinuityPhotoRequest(
          [void Function(LinkContinuityPhotoRequestBuilder)? updates]) =>
      (LinkContinuityPhotoRequestBuilder()..update(updates))._build();

  _$LinkContinuityPhotoRequest._({required this.photoId, required this.version})
      : super._();
  @override
  LinkContinuityPhotoRequest rebuild(
          void Function(LinkContinuityPhotoRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LinkContinuityPhotoRequestBuilder toBuilder() =>
      LinkContinuityPhotoRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LinkContinuityPhotoRequest &&
        photoId == other.photoId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, photoId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LinkContinuityPhotoRequest')
          ..add('photoId', photoId)
          ..add('version', version))
        .toString();
  }
}

class LinkContinuityPhotoRequestBuilder
    implements
        Builder<LinkContinuityPhotoRequest, LinkContinuityPhotoRequestBuilder> {
  _$LinkContinuityPhotoRequest? _$v;

  String? _photoId;
  String? get photoId => _$this._photoId;
  set photoId(String? photoId) => _$this._photoId = photoId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  LinkContinuityPhotoRequestBuilder() {
    LinkContinuityPhotoRequest._defaults(this);
  }

  LinkContinuityPhotoRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _photoId = $v.photoId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LinkContinuityPhotoRequest other) {
    _$v = other as _$LinkContinuityPhotoRequest;
  }

  @override
  void update(void Function(LinkContinuityPhotoRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LinkContinuityPhotoRequest build() => _build();

  _$LinkContinuityPhotoRequest _build() {
    final _$result = _$v ??
        _$LinkContinuityPhotoRequest._(
          photoId: BuiltValueNullFieldError.checkNotNull(
              photoId, r'LinkContinuityPhotoRequest', 'photoId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'LinkContinuityPhotoRequest', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
