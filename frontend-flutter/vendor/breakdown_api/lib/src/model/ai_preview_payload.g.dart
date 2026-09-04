// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_preview_payload.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AiPreviewPayloadKindEnum _$aiPreviewPayloadKindEnum_merged =
    const AiPreviewPayloadKindEnum._('merged');

AiPreviewPayloadKindEnum _$aiPreviewPayloadKindEnumValueOf(String name) {
  switch (name) {
    case 'merged':
      return _$aiPreviewPayloadKindEnum_merged;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AiPreviewPayloadKindEnum> _$aiPreviewPayloadKindEnumValues =
    BuiltSet<AiPreviewPayloadKindEnum>(const <AiPreviewPayloadKindEnum>[
  _$aiPreviewPayloadKindEnum_merged,
]);

Serializer<AiPreviewPayloadKindEnum> _$aiPreviewPayloadKindEnumSerializer =
    _$AiPreviewPayloadKindEnumSerializer();

class _$AiPreviewPayloadKindEnumSerializer
    implements PrimitiveSerializer<AiPreviewPayloadKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'merged': 'merged',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'merged': 'merged',
  };

  @override
  final Iterable<Type> types = const <Type>[AiPreviewPayloadKindEnum];
  @override
  final String wireName = 'AiPreviewPayloadKindEnum';

  @override
  Object serialize(Serializers serializers, AiPreviewPayloadKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AiPreviewPayloadKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AiPreviewPayloadKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AiPreviewPayload extends AiPreviewPayload {
  @override
  final OneOf oneOf;

  factory _$AiPreviewPayload(
          [void Function(AiPreviewPayloadBuilder)? updates]) =>
      (AiPreviewPayloadBuilder()..update(updates))._build();

  _$AiPreviewPayload._({required this.oneOf}) : super._();
  @override
  AiPreviewPayload rebuild(void Function(AiPreviewPayloadBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiPreviewPayloadBuilder toBuilder() =>
      AiPreviewPayloadBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiPreviewPayload && oneOf == other.oneOf;
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
    return (newBuiltValueToStringHelper(r'AiPreviewPayload')
          ..add('oneOf', oneOf))
        .toString();
  }
}

class AiPreviewPayloadBuilder
    implements Builder<AiPreviewPayload, AiPreviewPayloadBuilder> {
  _$AiPreviewPayload? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  AiPreviewPayloadBuilder() {
    AiPreviewPayload._defaults(this);
  }

  AiPreviewPayloadBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiPreviewPayload other) {
    _$v = other as _$AiPreviewPayload;
  }

  @override
  void update(void Function(AiPreviewPayloadBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiPreviewPayload build() => _build();

  _$AiPreviewPayload _build() {
    final _$result = _$v ??
        _$AiPreviewPayload._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'AiPreviewPayload', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
