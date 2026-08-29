// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_mapping_decision_one_of_update.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$ApplyMappingDecisionOneOfUpdate
    extends ApplyMappingDecisionOneOfUpdate {
  @override
  final String aggregateId;
  @override
  final int version;

  factory _$ApplyMappingDecisionOneOfUpdate(
          [void Function(ApplyMappingDecisionOneOfUpdateBuilder)? updates]) =>
      (ApplyMappingDecisionOneOfUpdateBuilder()..update(updates))._build();

  _$ApplyMappingDecisionOneOfUpdate._(
      {required this.aggregateId, required this.version})
      : super._();
  @override
  ApplyMappingDecisionOneOfUpdate rebuild(
          void Function(ApplyMappingDecisionOneOfUpdateBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyMappingDecisionOneOfUpdateBuilder toBuilder() =>
      ApplyMappingDecisionOneOfUpdateBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyMappingDecisionOneOfUpdate &&
        aggregateId == other.aggregateId &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, aggregateId.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyMappingDecisionOneOfUpdate')
          ..add('aggregateId', aggregateId)
          ..add('version', version))
        .toString();
  }
}

class ApplyMappingDecisionOneOfUpdateBuilder
    implements
        Builder<ApplyMappingDecisionOneOfUpdate,
            ApplyMappingDecisionOneOfUpdateBuilder> {
  _$ApplyMappingDecisionOneOfUpdate? _$v;

  String? _aggregateId;
  String? get aggregateId => _$this._aggregateId;
  set aggregateId(String? aggregateId) => _$this._aggregateId = aggregateId;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  ApplyMappingDecisionOneOfUpdateBuilder() {
    ApplyMappingDecisionOneOfUpdate._defaults(this);
  }

  ApplyMappingDecisionOneOfUpdateBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _aggregateId = $v.aggregateId;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyMappingDecisionOneOfUpdate other) {
    _$v = other as _$ApplyMappingDecisionOneOfUpdate;
  }

  @override
  void update(void Function(ApplyMappingDecisionOneOfUpdateBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyMappingDecisionOneOfUpdate build() => _build();

  _$ApplyMappingDecisionOneOfUpdate _build() {
    final _$result = _$v ??
        _$ApplyMappingDecisionOneOfUpdate._(
          aggregateId: BuiltValueNullFieldError.checkNotNull(
              aggregateId, r'ApplyMappingDecisionOneOfUpdate', 'aggregateId'),
          version: BuiltValueNullFieldError.checkNotNull(
              version, r'ApplyMappingDecisionOneOfUpdate', 'version'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
