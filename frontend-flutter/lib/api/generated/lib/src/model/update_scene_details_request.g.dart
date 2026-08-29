// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_scene_details_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateSceneDetailsRequest extends UpdateSceneDetailsRequest {
  @override
  final SceneDetails details;
  @override
  final int version;

  factory _$UpdateSceneDetailsRequest(
          [void Function(UpdateSceneDetailsRequestBuilder)? updates]) =>
      (UpdateSceneDetailsRequestBuilder()..update(updates))._build();

  _$UpdateSceneDetailsRequest._({required this.details, required this.version})
      : super._();
  @override
  UpdateSceneDetailsRequest rebuild(
          void Function(UpdateSceneDetailsRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateSceneDetailsRequestBuilder toBuilder() =>
      UpdateSceneDetailsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateSceneDetailsRequest &&
        details == other.details &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, details.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateSceneDetailsRequest')
          ..add('details', details)
          ..add('version', version))
        .toString();
  }
}

class UpdateSceneDetailsRequestBuilder
    implements
        Builder<UpdateSceneDetailsRequest, UpdateSceneDetailsRequestBuilder> {
  _$UpdateSceneDetailsRequest? _$v;

  SceneDetailsBuilder? _details;
  SceneDetailsBuilder get details => _$this._details ??= SceneDetailsBuilder();
  set details(SceneDetailsBuilder? details) => _$this._details = details;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateSceneDetailsRequestBuilder() {
    UpdateSceneDetailsRequest._defaults(this);
  }

  UpdateSceneDetailsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _details = $v.details.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateSceneDetailsRequest other) {
    _$v = other as _$UpdateSceneDetailsRequest;
  }

  @override
  void update(void Function(UpdateSceneDetailsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateSceneDetailsRequest build() => _build();

  _$UpdateSceneDetailsRequest _build() {
    _$UpdateSceneDetailsRequest _$result;
    try {
      _$result = _$v ??
          _$UpdateSceneDetailsRequest._(
            details: details.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'UpdateSceneDetailsRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'details';
        details.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'UpdateSceneDetailsRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
