// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_run_outcome_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ApplyRunOutcomeOneOfOutcomeEnum
    _$applyRunOutcomeOneOfOutcomeEnum_succeeded =
    const ApplyRunOutcomeOneOfOutcomeEnum._('succeeded');

ApplyRunOutcomeOneOfOutcomeEnum _$applyRunOutcomeOneOfOutcomeEnumValueOf(
    String name) {
  switch (name) {
    case 'succeeded':
      return _$applyRunOutcomeOneOfOutcomeEnum_succeeded;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ApplyRunOutcomeOneOfOutcomeEnum>
    _$applyRunOutcomeOneOfOutcomeEnumValues = BuiltSet<
        ApplyRunOutcomeOneOfOutcomeEnum>(const <ApplyRunOutcomeOneOfOutcomeEnum>[
  _$applyRunOutcomeOneOfOutcomeEnum_succeeded,
]);

Serializer<ApplyRunOutcomeOneOfOutcomeEnum>
    _$applyRunOutcomeOneOfOutcomeEnumSerializer =
    _$ApplyRunOutcomeOneOfOutcomeEnumSerializer();

class _$ApplyRunOutcomeOneOfOutcomeEnumSerializer
    implements PrimitiveSerializer<ApplyRunOutcomeOneOfOutcomeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'succeeded': 'succeeded',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'succeeded': 'succeeded',
  };

  @override
  final Iterable<Type> types = const <Type>[ApplyRunOutcomeOneOfOutcomeEnum];
  @override
  final String wireName = 'ApplyRunOutcomeOneOfOutcomeEnum';

  @override
  Object serialize(
          Serializers serializers, ApplyRunOutcomeOneOfOutcomeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ApplyRunOutcomeOneOfOutcomeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ApplyRunOutcomeOneOfOutcomeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$ApplyRunOutcomeOneOf extends ApplyRunOutcomeOneOf {
  @override
  final ApplyRunOutcomeOneOfOutcomeEnum outcome;
  @override
  final ApplyImportSummary summary;

  factory _$ApplyRunOutcomeOneOf(
          [void Function(ApplyRunOutcomeOneOfBuilder)? updates]) =>
      (ApplyRunOutcomeOneOfBuilder()..update(updates))._build();

  _$ApplyRunOutcomeOneOf._({required this.outcome, required this.summary})
      : super._();
  @override
  ApplyRunOutcomeOneOf rebuild(
          void Function(ApplyRunOutcomeOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  ApplyRunOutcomeOneOfBuilder toBuilder() =>
      ApplyRunOutcomeOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is ApplyRunOutcomeOneOf &&
        outcome == other.outcome &&
        summary == other.summary;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, outcome.hashCode);
    _$hash = $jc(_$hash, summary.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'ApplyRunOutcomeOneOf')
          ..add('outcome', outcome)
          ..add('summary', summary))
        .toString();
  }
}

class ApplyRunOutcomeOneOfBuilder
    implements Builder<ApplyRunOutcomeOneOf, ApplyRunOutcomeOneOfBuilder> {
  _$ApplyRunOutcomeOneOf? _$v;

  ApplyRunOutcomeOneOfOutcomeEnum? _outcome;
  ApplyRunOutcomeOneOfOutcomeEnum? get outcome => _$this._outcome;
  set outcome(ApplyRunOutcomeOneOfOutcomeEnum? outcome) =>
      _$this._outcome = outcome;

  ApplyImportSummaryBuilder? _summary;
  ApplyImportSummaryBuilder get summary =>
      _$this._summary ??= ApplyImportSummaryBuilder();
  set summary(ApplyImportSummaryBuilder? summary) => _$this._summary = summary;

  ApplyRunOutcomeOneOfBuilder() {
    ApplyRunOutcomeOneOf._defaults(this);
  }

  ApplyRunOutcomeOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _outcome = $v.outcome;
      _summary = $v.summary.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(ApplyRunOutcomeOneOf other) {
    _$v = other as _$ApplyRunOutcomeOneOf;
  }

  @override
  void update(void Function(ApplyRunOutcomeOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  ApplyRunOutcomeOneOf build() => _build();

  _$ApplyRunOutcomeOneOf _build() {
    _$ApplyRunOutcomeOneOf _$result;
    try {
      _$result = _$v ??
          _$ApplyRunOutcomeOneOf._(
            outcome: BuiltValueNullFieldError.checkNotNull(
                outcome, r'ApplyRunOutcomeOneOf', 'outcome'),
            summary: summary.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'summary';
        summary.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'ApplyRunOutcomeOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
