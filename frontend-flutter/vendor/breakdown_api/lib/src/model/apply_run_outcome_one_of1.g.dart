// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_run_outcome_one_of1.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ApplyRunOutcomeOneOf1OutcomeEnum
    _$applyRunOutcomeOneOf1OutcomeEnum_failed =
    const ApplyRunOutcomeOneOf1OutcomeEnum._('failed');

ApplyRunOutcomeOneOf1OutcomeEnum _$applyRunOutcomeOneOf1OutcomeEnumValueOf(
    String name) {
  switch (name) {
    case 'failed':
      return _$applyRunOutcomeOneOf1OutcomeEnum_failed;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ApplyRunOutcomeOneOf1OutcomeEnum>
    _$applyRunOutcomeOneOf1OutcomeEnumValues = BuiltSet<
        ApplyRunOutcomeOneOf1OutcomeEnum>(const <ApplyRunOutcomeOneOf1OutcomeEnum>[
  _$applyRunOutcomeOneOf1OutcomeEnum_failed,
]);

Serializer<ApplyRunOutcomeOneOf1OutcomeEnum>
    _$applyRunOutcomeOneOf1OutcomeEnumSerializer =
    _$ApplyRunOutcomeOneOf1OutcomeEnumSerializer();

class _$ApplyRunOutcomeOneOf1OutcomeEnumSerializer
    implements PrimitiveSerializer<ApplyRunOutcomeOneOf1OutcomeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'failed': 'failed',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'failed': 'failed',
  };

  @override
  final Iterable<Type> types = const <Type>[ApplyRunOutcomeOneOf1OutcomeEnum];
  @override
  final String wireName = 'ApplyRunOutcomeOneOf1OutcomeEnum';

  @override
  Object serialize(
          Serializers serializers, ApplyRunOutcomeOneOf1OutcomeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ApplyRunOutcomeOneOf1OutcomeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ApplyRunOutcomeOneOf1OutcomeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ApplyRunOutcomeOneOf1 extends ApplyRunOutcomeOneOf1 {
  @override
  final String code;
  @override
  final ApplyRunOutcomeOneOf1OutcomeEnum outcome;

  factory _$ApplyRunOutcomeOneOf1(
          [void Function(ApplyRunOutcomeOneOf1Builder)? updates]) =>
      (ApplyRunOutcomeOneOf1Builder()..update(updates))._build();

  _$ApplyRunOutcomeOneOf1._({required this.code, required this.outcome})
      : super._();
  @override
  ApplyRunOutcomeOneOf1 rebuild(
          void Function(ApplyRunOutcomeOneOf1Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyRunOutcomeOneOf1Builder toBuilder() =>
      ApplyRunOutcomeOneOf1Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyRunOutcomeOneOf1 &&
        code == other.code &&
        outcome == other.outcome;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, code.hashCode);
    _$hash = $jc(_$hash, outcome.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyRunOutcomeOneOf1')
          ..add('code', code)
          ..add('outcome', outcome))
        .toString();
  }
}

class ApplyRunOutcomeOneOf1Builder
    implements Builder<ApplyRunOutcomeOneOf1, ApplyRunOutcomeOneOf1Builder> {
  _$ApplyRunOutcomeOneOf1? _$v;

  String? _code;
  String? get code => _$this._code;
  set code(String? code) => _$this._code = code;

  ApplyRunOutcomeOneOf1OutcomeEnum? _outcome;
  ApplyRunOutcomeOneOf1OutcomeEnum? get outcome => _$this._outcome;
  set outcome(ApplyRunOutcomeOneOf1OutcomeEnum? outcome) =>
      _$this._outcome = outcome;

  ApplyRunOutcomeOneOf1Builder() {
    ApplyRunOutcomeOneOf1._defaults(this);
  }

  ApplyRunOutcomeOneOf1Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _code = $v.code;
      _outcome = $v.outcome;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyRunOutcomeOneOf1 other) {
    _$v = other as _$ApplyRunOutcomeOneOf1;
  }

  @override
  void update(void Function(ApplyRunOutcomeOneOf1Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyRunOutcomeOneOf1 build() => _build();

  _$ApplyRunOutcomeOneOf1 _build() {
    final _$result = _$v ??
        _$ApplyRunOutcomeOneOf1._(
          code: BuiltValueNullFieldError.checkNotNull(
              code, r'ApplyRunOutcomeOneOf1', 'code'),
          outcome: BuiltValueNullFieldError.checkNotNull(
              outcome, r'ApplyRunOutcomeOneOf1', 'outcome'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
