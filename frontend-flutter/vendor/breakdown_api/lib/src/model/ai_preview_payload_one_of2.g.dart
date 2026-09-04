// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_preview_payload_one_of2.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AiPreviewPayloadOneOf2KindEnum _$aiPreviewPayloadOneOf2KindEnum_merged =
    const AiPreviewPayloadOneOf2KindEnum._('merged');

AiPreviewPayloadOneOf2KindEnum _$aiPreviewPayloadOneOf2KindEnumValueOf(
    String name) {
  switch (name) {
    case 'merged':
      return _$aiPreviewPayloadOneOf2KindEnum_merged;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AiPreviewPayloadOneOf2KindEnum>
    _$aiPreviewPayloadOneOf2KindEnumValues = BuiltSet<
        AiPreviewPayloadOneOf2KindEnum>(const <AiPreviewPayloadOneOf2KindEnum>[
  _$aiPreviewPayloadOneOf2KindEnum_merged,
]);

Serializer<AiPreviewPayloadOneOf2KindEnum>
    _$aiPreviewPayloadOneOf2KindEnumSerializer =
    _$AiPreviewPayloadOneOf2KindEnumSerializer();

class _$AiPreviewPayloadOneOf2KindEnumSerializer
    implements PrimitiveSerializer<AiPreviewPayloadOneOf2KindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'merged': 'merged',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'merged': 'merged',
  };

  @override
  final Iterable<Type> types = const <Type>[AiPreviewPayloadOneOf2KindEnum];
  @override
  final String wireName = 'AiPreviewPayloadOneOf2KindEnum';

  @override
  Object serialize(
          Serializers serializers, AiPreviewPayloadOneOf2KindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AiPreviewPayloadOneOf2KindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AiPreviewPayloadOneOf2KindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$AiPreviewPayloadOneOf2 extends AiPreviewPayloadOneOf2 {
  @override
  final MergedPreview data;
  @override
  final AiPreviewPayloadOneOf2KindEnum kind;

  factory _$AiPreviewPayloadOneOf2(
          [void Function(AiPreviewPayloadOneOf2Builder)? updates]) =>
      (AiPreviewPayloadOneOf2Builder()..update(updates))._build();

  _$AiPreviewPayloadOneOf2._({required this.data, required this.kind})
      : super._();
  @override
  AiPreviewPayloadOneOf2 rebuild(
          void Function(AiPreviewPayloadOneOf2Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiPreviewPayloadOneOf2Builder toBuilder() =>
      AiPreviewPayloadOneOf2Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiPreviewPayloadOneOf2 &&
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
    return (newBuiltValueToStringHelper(r'AiPreviewPayloadOneOf2')
          ..add('data', data)
          ..add('kind', kind))
        .toString();
  }
}

class AiPreviewPayloadOneOf2Builder
    implements Builder<AiPreviewPayloadOneOf2, AiPreviewPayloadOneOf2Builder> {
  _$AiPreviewPayloadOneOf2? _$v;

  MergedPreviewBuilder? _data;
  MergedPreviewBuilder get data => _$this._data ??= MergedPreviewBuilder();
  set data(MergedPreviewBuilder? data) => _$this._data = data;

  AiPreviewPayloadOneOf2KindEnum? _kind;
  AiPreviewPayloadOneOf2KindEnum? get kind => _$this._kind;
  set kind(AiPreviewPayloadOneOf2KindEnum? kind) => _$this._kind = kind;

  AiPreviewPayloadOneOf2Builder() {
    AiPreviewPayloadOneOf2._defaults(this);
  }

  AiPreviewPayloadOneOf2Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _data = $v.data.toBuilder();
      _kind = $v.kind;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiPreviewPayloadOneOf2 other) {
    _$v = other as _$AiPreviewPayloadOneOf2;
  }

  @override
  void update(void Function(AiPreviewPayloadOneOf2Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiPreviewPayloadOneOf2 build() => _build();

  _$AiPreviewPayloadOneOf2 _build() {
    _$AiPreviewPayloadOneOf2 _$result;
    try {
      _$result = _$v ??
          _$AiPreviewPayloadOneOf2._(
            data: data.build(),
            kind: BuiltValueNullFieldError.checkNotNull(
                kind, r'AiPreviewPayloadOneOf2', 'kind'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'data';
        data.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AiPreviewPayloadOneOf2', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
