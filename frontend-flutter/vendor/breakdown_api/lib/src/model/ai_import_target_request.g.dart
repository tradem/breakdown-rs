// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_target_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportTargetRequest extends AiImportTargetRequest {
  @override
  final String blockId;

  factory _$AiImportTargetRequest(
          [void Function(AiImportTargetRequestBuilder)? updates]) =>
      (AiImportTargetRequestBuilder()..update(updates))._build();

  _$AiImportTargetRequest._({required this.blockId}) : super._();
  @override
  AiImportTargetRequest rebuild(
          void Function(AiImportTargetRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportTargetRequestBuilder toBuilder() =>
      AiImportTargetRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportTargetRequest && blockId == other.blockId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportTargetRequest')
          ..add('blockId', blockId))
        .toString();
  }
}

class AiImportTargetRequestBuilder
    implements Builder<AiImportTargetRequest, AiImportTargetRequestBuilder> {
  _$AiImportTargetRequest? _$v;

  String? _blockId;
  String? get blockId => _$this._blockId;
  set blockId(String? blockId) => _$this._blockId = blockId;

  AiImportTargetRequestBuilder() {
    AiImportTargetRequest._defaults(this);
  }

  AiImportTargetRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _blockId = $v.blockId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportTargetRequest other) {
    _$v = other as _$AiImportTargetRequest;
  }

  @override
  void update(void Function(AiImportTargetRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportTargetRequest build() => _build();

  _$AiImportTargetRequest _build() {
    final _$result = _$v ??
        _$AiImportTargetRequest._(
          blockId: BuiltValueNullFieldError.checkNotNull(
              blockId, r'AiImportTargetRequest', 'blockId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
