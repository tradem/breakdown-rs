// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_scene_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateSceneRequest extends CreateSceneRequest {
  @override
  final SceneDetails details;
  @override
  final String episodeId;

  factory _$CreateSceneRequest(
          [void Function(CreateSceneRequestBuilder)? updates]) =>
      (CreateSceneRequestBuilder()..update(updates))._build();

  _$CreateSceneRequest._({required this.details, required this.episodeId})
      : super._();
  @override
  CreateSceneRequest rebuild(
          void Function(CreateSceneRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateSceneRequestBuilder toBuilder() =>
      CreateSceneRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateSceneRequest &&
        details == other.details &&
        episodeId == other.episodeId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, details.hashCode);
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateSceneRequest')
          ..add('details', details)
          ..add('episodeId', episodeId))
        .toString();
  }
}

class CreateSceneRequestBuilder
    implements Builder<CreateSceneRequest, CreateSceneRequestBuilder> {
  _$CreateSceneRequest? _$v;

  SceneDetailsBuilder? _details;
  SceneDetailsBuilder get details => _$this._details ??= SceneDetailsBuilder();
  set details(SceneDetailsBuilder? details) => _$this._details = details;

  String? _episodeId;
  String? get episodeId => _$this._episodeId;
  set episodeId(String? episodeId) => _$this._episodeId = episodeId;

  CreateSceneRequestBuilder() {
    CreateSceneRequest._defaults(this);
  }

  CreateSceneRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _details = $v.details.toBuilder();
      _episodeId = $v.episodeId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateSceneRequest other) {
    _$v = other as _$CreateSceneRequest;
  }

  @override
  void update(void Function(CreateSceneRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateSceneRequest build() => _build();

  _$CreateSceneRequest _build() {
    _$CreateSceneRequest _$result;
    try {
      _$result = _$v ??
          _$CreateSceneRequest._(
            details: details.build(),
            episodeId: BuiltValueNullFieldError.checkNotNull(
                episodeId, r'CreateSceneRequest', 'episodeId'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'details';
        details.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CreateSceneRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
