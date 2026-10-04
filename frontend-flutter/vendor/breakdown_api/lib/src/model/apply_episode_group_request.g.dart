// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_episode_group_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyEpisodeGroupRequest extends ApplyEpisodeGroupRequest {
  @override
  final String episodeRef;
  @override
  final EpisodeTarget target;

  factory _$ApplyEpisodeGroupRequest(
          [void Function(ApplyEpisodeGroupRequestBuilder)? updates]) =>
      (ApplyEpisodeGroupRequestBuilder()..update(updates))._build();

  _$ApplyEpisodeGroupRequest._({required this.episodeRef, required this.target})
      : super._();
  @override
  ApplyEpisodeGroupRequest rebuild(
          void Function(ApplyEpisodeGroupRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyEpisodeGroupRequestBuilder toBuilder() =>
      ApplyEpisodeGroupRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyEpisodeGroupRequest &&
        episodeRef == other.episodeRef &&
        target == other.target;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, episodeRef.hashCode);
    _$hash = $jc(_$hash, target.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyEpisodeGroupRequest')
          ..add('episodeRef', episodeRef)
          ..add('target', target))
        .toString();
  }
}

class ApplyEpisodeGroupRequestBuilder
    implements
        Builder<ApplyEpisodeGroupRequest, ApplyEpisodeGroupRequestBuilder> {
  _$ApplyEpisodeGroupRequest? _$v;

  String? _episodeRef;
  String? get episodeRef => _$this._episodeRef;
  set episodeRef(String? episodeRef) => _$this._episodeRef = episodeRef;

  EpisodeTargetBuilder? _target;
  EpisodeTargetBuilder get target => _$this._target ??= EpisodeTargetBuilder();
  set target(EpisodeTargetBuilder? target) => _$this._target = target;

  ApplyEpisodeGroupRequestBuilder() {
    ApplyEpisodeGroupRequest._defaults(this);
  }

  ApplyEpisodeGroupRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _episodeRef = $v.episodeRef;
      _target = $v.target.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyEpisodeGroupRequest other) {
    _$v = other as _$ApplyEpisodeGroupRequest;
  }

  @override
  void update(void Function(ApplyEpisodeGroupRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyEpisodeGroupRequest build() => _build();

  _$ApplyEpisodeGroupRequest _build() {
    _$ApplyEpisodeGroupRequest _$result;
    try {
      _$result = _$v ??
          _$ApplyEpisodeGroupRequest._(
            episodeRef: BuiltValueNullFieldError.checkNotNull(
                episodeRef, r'ApplyEpisodeGroupRequest', 'episodeRef'),
            target: target.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'target';
        target.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyEpisodeGroupRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
