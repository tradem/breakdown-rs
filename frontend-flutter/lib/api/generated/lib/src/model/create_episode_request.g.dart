// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_episode_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CreateEpisodeRequest extends CreateEpisodeRequest {
  @override
  final String blockId;
  @override
  final String? name;
  @override
  final int number;
  @override
  final String seriesId;

  factory _$CreateEpisodeRequest(
          [void Function(CreateEpisodeRequestBuilder)? updates]) =>
      (CreateEpisodeRequestBuilder()..update(updates))._build();

  _$CreateEpisodeRequest._(
      {required this.blockId,
      this.name,
      required this.number,
      required this.seriesId})
      : super._();
  @override
  CreateEpisodeRequest rebuild(
          void Function(CreateEpisodeRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CreateEpisodeRequestBuilder toBuilder() =>
      CreateEpisodeRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CreateEpisodeRequest &&
        blockId == other.blockId &&
        name == other.name &&
        number == other.number &&
        seriesId == other.seriesId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jc(_$hash, seriesId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CreateEpisodeRequest')
          ..add('blockId', blockId)
          ..add('name', name)
          ..add('number', number)
          ..add('seriesId', seriesId))
        .toString();
  }
}

class CreateEpisodeRequestBuilder
    implements Builder<CreateEpisodeRequest, CreateEpisodeRequestBuilder> {
  _$CreateEpisodeRequest? _$v;

  String? _blockId;
  String? get blockId => _$this._blockId;
  set blockId(String? blockId) => _$this._blockId = blockId;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  String? _seriesId;
  String? get seriesId => _$this._seriesId;
  set seriesId(String? seriesId) => _$this._seriesId = seriesId;

  CreateEpisodeRequestBuilder() {
    CreateEpisodeRequest._defaults(this);
  }

  CreateEpisodeRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _blockId = $v.blockId;
      _name = $v.name;
      _number = $v.number;
      _seriesId = $v.seriesId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CreateEpisodeRequest other) {
    _$v = other as _$CreateEpisodeRequest;
  }

  @override
  void update(void Function(CreateEpisodeRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CreateEpisodeRequest build() => _build();

  _$CreateEpisodeRequest _build() {
    final _$result = _$v ??
        _$CreateEpisodeRequest._(
          blockId: BuiltValueNullFieldError.checkNotNull(
              blockId, r'CreateEpisodeRequest', 'blockId'),
          name: name,
          number: BuiltValueNullFieldError.checkNotNull(
              number, r'CreateEpisodeRequest', 'number'),
          seriesId: BuiltValueNullFieldError.checkNotNull(
              seriesId, r'CreateEpisodeRequest', 'seriesId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
