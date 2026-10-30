// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_target.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportTarget extends AiImportTarget {
  @override
  final int blockNumber;
  @override
  final String seasonId;
  @override
  final int seasonNumber;

  factory _$AiImportTarget([void Function(AiImportTargetBuilder)? updates]) =>
      (AiImportTargetBuilder()..update(updates))._build();

  _$AiImportTarget._(
      {required this.blockNumber,
      required this.seasonId,
      required this.seasonNumber})
      : super._();
  @override
  AiImportTarget rebuild(void Function(AiImportTargetBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportTargetBuilder toBuilder() => AiImportTargetBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportTarget &&
        blockNumber == other.blockNumber &&
        seasonId == other.seasonId &&
        seasonNumber == other.seasonNumber;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, blockNumber.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jc(_$hash, seasonNumber.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportTarget')
          ..add('blockNumber', blockNumber)
          ..add('seasonId', seasonId)
          ..add('seasonNumber', seasonNumber))
        .toString();
  }
}

class AiImportTargetBuilder
    implements Builder<AiImportTarget, AiImportTargetBuilder> {
  _$AiImportTarget? _$v;

  int? _blockNumber;
  int? get blockNumber => _$this._blockNumber;
  set blockNumber(int? blockNumber) => _$this._blockNumber = blockNumber;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  int? _seasonNumber;
  int? get seasonNumber => _$this._seasonNumber;
  set seasonNumber(int? seasonNumber) => _$this._seasonNumber = seasonNumber;

  AiImportTargetBuilder() {
    AiImportTarget._defaults(this);
  }

  AiImportTargetBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _blockNumber = $v.blockNumber;
      _seasonId = $v.seasonId;
      _seasonNumber = $v.seasonNumber;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportTarget other) {
    _$v = other as _$AiImportTarget;
  }

  @override
  void update(void Function(AiImportTargetBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportTarget build() => _build();

  _$AiImportTarget _build() {
    final _$result = _$v ??
        _$AiImportTarget._(
          blockNumber: BuiltValueNullFieldError.checkNotNull(
              blockNumber, r'AiImportTarget', 'blockNumber'),
          seasonId: BuiltValueNullFieldError.checkNotNull(
              seasonId, r'AiImportTarget', 'seasonId'),
          seasonNumber: BuiltValueNullFieldError.checkNotNull(
              seasonNumber, r'AiImportTarget', 'seasonNumber'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
