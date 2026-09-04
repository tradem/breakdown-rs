// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_preview_payload_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AiPreviewPayloadOneOfKindEnum _$aiPreviewPayloadOneOfKindEnum_script =
    const AiPreviewPayloadOneOfKindEnum._('script');

AiPreviewPayloadOneOfKindEnum _$aiPreviewPayloadOneOfKindEnumValueOf(
    String name) {
  switch (name) {
    case 'script':
      return _$aiPreviewPayloadOneOfKindEnum_script;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AiPreviewPayloadOneOfKindEnum>
    _$aiPreviewPayloadOneOfKindEnumValues = BuiltSet<
        AiPreviewPayloadOneOfKindEnum>(const <AiPreviewPayloadOneOfKindEnum>[
  _$aiPreviewPayloadOneOfKindEnum_script,
]);

Serializer<AiPreviewPayloadOneOfKindEnum>
    _$aiPreviewPayloadOneOfKindEnumSerializer =
    _$AiPreviewPayloadOneOfKindEnumSerializer();

class _$AiPreviewPayloadOneOfKindEnumSerializer
    implements PrimitiveSerializer<AiPreviewPayloadOneOfKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'script': 'script',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'script': 'script',
  };

  @override
  final Iterable<Type> types = const <Type>[AiPreviewPayloadOneOfKindEnum];
  @override
  final String wireName = 'AiPreviewPayloadOneOfKindEnum';

  @override
  Object serialize(
          Serializers serializers, AiPreviewPayloadOneOfKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AiPreviewPayloadOneOfKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AiPreviewPayloadOneOfKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AiPreviewPayloadOneOf extends AiPreviewPayloadOneOf {
  @override
  final ScriptContext data;
  @override
  final AiPreviewPayloadOneOfKindEnum kind;

  factory _$AiPreviewPayloadOneOf(
          [void Function(AiPreviewPayloadOneOfBuilder)? updates]) =>
      (AiPreviewPayloadOneOfBuilder()..update(updates))._build();

  _$AiPreviewPayloadOneOf._({required this.data, required this.kind})
      : super._();
  @override
  AiPreviewPayloadOneOf rebuild(
          void Function(AiPreviewPayloadOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiPreviewPayloadOneOfBuilder toBuilder() =>
      AiPreviewPayloadOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiPreviewPayloadOneOf &&
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
    return (newBuiltValueToStringHelper(r'AiPreviewPayloadOneOf')
          ..add('data', data)
          ..add('kind', kind))
        .toString();
  }
}

class AiPreviewPayloadOneOfBuilder
    implements Builder<AiPreviewPayloadOneOf, AiPreviewPayloadOneOfBuilder> {
  _$AiPreviewPayloadOneOf? _$v;

  ScriptContextBuilder? _data;
  ScriptContextBuilder get data => _$this._data ??= ScriptContextBuilder();
  set data(ScriptContextBuilder? data) => _$this._data = data;

  AiPreviewPayloadOneOfKindEnum? _kind;
  AiPreviewPayloadOneOfKindEnum? get kind => _$this._kind;
  set kind(AiPreviewPayloadOneOfKindEnum? kind) => _$this._kind = kind;

  AiPreviewPayloadOneOfBuilder() {
    AiPreviewPayloadOneOf._defaults(this);
  }

  AiPreviewPayloadOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _data = $v.data.toBuilder();
      _kind = $v.kind;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiPreviewPayloadOneOf other) {
    _$v = other as _$AiPreviewPayloadOneOf;
  }

  @override
  void update(void Function(AiPreviewPayloadOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiPreviewPayloadOneOf build() => _build();

  _$AiPreviewPayloadOneOf _build() {
    _$AiPreviewPayloadOneOf _$result;
    try {
      _$result = _$v ??
          _$AiPreviewPayloadOneOf._(
            data: data.build(),
            kind: BuiltValueNullFieldError.checkNotNull(
                kind, r'AiPreviewPayloadOneOf', 'kind'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        data.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiPreviewPayloadOneOf', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
