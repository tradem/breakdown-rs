// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_run_outcome.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ApplyRunOutcomeOutcomeEnum _$applyRunOutcomeOutcomeEnum_failed =
    const ApplyRunOutcomeOutcomeEnum._('failed');

ApplyRunOutcomeOutcomeEnum _$applyRunOutcomeOutcomeEnumValueOf(String name) {
  switch (name) {
    case 'failed':
      return _$applyRunOutcomeOutcomeEnum_failed;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ApplyRunOutcomeOutcomeEnum> _$applyRunOutcomeOutcomeEnumValues =
    BuiltSet<ApplyRunOutcomeOutcomeEnum>(const <ApplyRunOutcomeOutcomeEnum>[
  _$applyRunOutcomeOutcomeEnum_failed,
]);

Serializer<ApplyRunOutcomeOutcomeEnum> _$applyRunOutcomeOutcomeEnumSerializer =
    _$ApplyRunOutcomeOutcomeEnumSerializer();

class _$ApplyRunOutcomeOutcomeEnumSerializer
    implements PrimitiveSerializer<ApplyRunOutcomeOutcomeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'failed': 'failed',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'failed': 'failed',
  };

  @override
  final Iterable<Type> types = const <Type>[ApplyRunOutcomeOutcomeEnum];
  @override
  final String wireName = 'ApplyRunOutcomeOutcomeEnum';

  @override
  Object serialize(Serializers serializers, ApplyRunOutcomeOutcomeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ApplyRunOutcomeOutcomeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ApplyRunOutcomeOutcomeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ApplyRunOutcome extends ApplyRunOutcome {
  @override
  final OneOf oneOf;

  factory _$ApplyRunOutcome([void Function(ApplyRunOutcomeBuilder)? updates]) =>
      (ApplyRunOutcomeBuilder()..update(updates))._build();

  _$ApplyRunOutcome._({required this.oneOf}) : super._();
  @override
  ApplyRunOutcome rebuild(void Function(ApplyRunOutcomeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyRunOutcomeBuilder toBuilder() => ApplyRunOutcomeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyRunOutcome && oneOf == other.oneOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, oneOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyRunOutcome')
          ..add('oneOf', oneOf))
        .toString();
  }
}

class ApplyRunOutcomeBuilder
    implements Builder<ApplyRunOutcome, ApplyRunOutcomeBuilder> {
  _$ApplyRunOutcome? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  ApplyRunOutcomeBuilder() {
    ApplyRunOutcome._defaults(this);
  }

  ApplyRunOutcomeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyRunOutcome other) {
    _$v = other as _$ApplyRunOutcome;
  }

  @override
  void update(void Function(ApplyRunOutcomeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyRunOutcome build() => _build();

  _$ApplyRunOutcome _build() {
    final _$result = _$v ??
        _$ApplyRunOutcome._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'ApplyRunOutcome', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
