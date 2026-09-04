// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_preview_payload_one_of1.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AiPreviewPayloadOneOf1KindEnum _$aiPreviewPayloadOneOf1KindEnum_schedule =
    const AiPreviewPayloadOneOf1KindEnum._('schedule');

AiPreviewPayloadOneOf1KindEnum _$aiPreviewPayloadOneOf1KindEnumValueOf(
    String name) {
  switch (name) {
    case 'schedule':
      return _$aiPreviewPayloadOneOf1KindEnum_schedule;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AiPreviewPayloadOneOf1KindEnum>
    _$aiPreviewPayloadOneOf1KindEnumValues = BuiltSet<
        AiPreviewPayloadOneOf1KindEnum>(const <AiPreviewPayloadOneOf1KindEnum>[
  _$aiPreviewPayloadOneOf1KindEnum_schedule,
]);

Serializer<AiPreviewPayloadOneOf1KindEnum>
    _$aiPreviewPayloadOneOf1KindEnumSerializer =
    _$AiPreviewPayloadOneOf1KindEnumSerializer();

class _$AiPreviewPayloadOneOf1KindEnumSerializer
    implements PrimitiveSerializer<AiPreviewPayloadOneOf1KindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'schedule': 'schedule',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'schedule': 'schedule',
  };

  @override
  final Iterable<Type> types = const <Type>[AiPreviewPayloadOneOf1KindEnum];
  @override
  final String wireName = 'AiPreviewPayloadOneOf1KindEnum';

  @override
  Object serialize(
          Serializers serializers, AiPreviewPayloadOneOf1KindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AiPreviewPayloadOneOf1KindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AiPreviewPayloadOneOf1KindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AiPreviewPayloadOneOf1 extends AiPreviewPayloadOneOf1 {
  @override
  final ShootingSchedule data;
  @override
  final AiPreviewPayloadOneOf1KindEnum kind;

  factory _$AiPreviewPayloadOneOf1(
          [void Function(AiPreviewPayloadOneOf1Builder)? updates]) =>
      (AiPreviewPayloadOneOf1Builder()..update(updates))._build();

  _$AiPreviewPayloadOneOf1._({required this.data, required this.kind})
      : super._();
  @override
  AiPreviewPayloadOneOf1 rebuild(
          void Function(AiPreviewPayloadOneOf1Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiPreviewPayloadOneOf1Builder toBuilder() =>
      AiPreviewPayloadOneOf1Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiPreviewPayloadOneOf1 &&
        data == other.data &&
        kind == other.kind;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, data.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiPreviewPayloadOneOf1')
          ..add('data', data)
          ..add('kind', kind))
        .toString();
  }
}

class AiPreviewPayloadOneOf1Builder
    implements Builder<AiPreviewPayloadOneOf1, AiPreviewPayloadOneOf1Builder> {
  _$AiPreviewPayloadOneOf1? _$v;

  ShootingScheduleBuilder? _data;
  ShootingScheduleBuilder get data =>
      _$this._data ??= ShootingScheduleBuilder();
  set data(ShootingScheduleBuilder? data) => _$this._data = data;

  AiPreviewPayloadOneOf1KindEnum? _kind;
  AiPreviewPayloadOneOf1KindEnum? get kind => _$this._kind;
  set kind(AiPreviewPayloadOneOf1KindEnum? kind) => _$this._kind = kind;

  AiPreviewPayloadOneOf1Builder() {
    AiPreviewPayloadOneOf1._defaults(this);
  }

  AiPreviewPayloadOneOf1Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _data = $v.data.toBuilder();
      _kind = $v.kind;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiPreviewPayloadOneOf1 other) {
    _$v = other as _$AiPreviewPayloadOneOf1;
  }

  @override
  void update(void Function(AiPreviewPayloadOneOf1Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiPreviewPayloadOneOf1 build() => _build();

  _$AiPreviewPayloadOneOf1 _build() {
    _$AiPreviewPayloadOneOf1 _$result;
    try {
      _$result = _$v ??
          _$AiPreviewPayloadOneOf1._(
            data: data.build(),
            kind: BuiltValueNullFieldError.checkNotNull(
                kind, r'AiPreviewPayloadOneOf1', 'kind'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        data.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiPreviewPayloadOneOf1', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
