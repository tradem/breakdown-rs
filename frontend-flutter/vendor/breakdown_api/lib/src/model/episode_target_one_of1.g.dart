// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_target_one_of1.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EpisodeTargetOneOf1KindEnum _$episodeTargetOneOf1KindEnum_create =
    const EpisodeTargetOneOf1KindEnum._('create');

EpisodeTargetOneOf1KindEnum _$episodeTargetOneOf1KindEnumValueOf(String name) {
  switch (name) {
    case 'create':
      return _$episodeTargetOneOf1KindEnum_create;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<EpisodeTargetOneOf1KindEnum>
    _$episodeTargetOneOf1KindEnumValues =
    BuiltSet<EpisodeTargetOneOf1KindEnum>(const <EpisodeTargetOneOf1KindEnum>[
  _$episodeTargetOneOf1KindEnum_create,
]);

Serializer<EpisodeTargetOneOf1KindEnum>
    _$episodeTargetOneOf1KindEnumSerializer =
    _$EpisodeTargetOneOf1KindEnumSerializer();

class _$EpisodeTargetOneOf1KindEnumSerializer
    implements PrimitiveSerializer<EpisodeTargetOneOf1KindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'create': 'create',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'create': 'create',
  };

  @override
  final Iterable<Type> types = const <Type>[EpisodeTargetOneOf1KindEnum];
  @override
  final String wireName = 'EpisodeTargetOneOf1KindEnum';

  @override
  Object serialize(Serializers serializers, EpisodeTargetOneOf1KindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  EpisodeTargetOneOf1KindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      EpisodeTargetOneOf1KindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$EpisodeTargetOneOf1 extends EpisodeTargetOneOf1 {
  @override
  final EpisodeTargetOneOf1KindEnum kind;
  @override
  final String? name;
  @override
  final int number;

  factory _$EpisodeTargetOneOf1(
          [void Function(EpisodeTargetOneOf1Builder)? updates]) =>
      (EpisodeTargetOneOf1Builder()..update(updates))._build();

  _$EpisodeTargetOneOf1._({required this.kind, this.name, required this.number})
      : super._();
  @override
  EpisodeTargetOneOf1 rebuild(
          void Function(EpisodeTargetOneOf1Builder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EpisodeTargetOneOf1Builder toBuilder() =>
      EpisodeTargetOneOf1Builder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EpisodeTargetOneOf1 &&
        kind == other.kind &&
        name == other.name &&
        number == other.number;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, number.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EpisodeTargetOneOf1')
          ..add('kind', kind)
          ..add('name', name)
          ..add('number', number))
        .toString();
  }
}

class EpisodeTargetOneOf1Builder
    implements Builder<EpisodeTargetOneOf1, EpisodeTargetOneOf1Builder> {
  _$EpisodeTargetOneOf1? _$v;

  EpisodeTargetOneOf1KindEnum? _kind;
  EpisodeTargetOneOf1KindEnum? get kind => _$this._kind;
  set kind(EpisodeTargetOneOf1KindEnum? kind) => _$this._kind = kind;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  int? _number;
  int? get number => _$this._number;
  set number(int? number) => _$this._number = number;

  EpisodeTargetOneOf1Builder() {
    EpisodeTargetOneOf1._defaults(this);
  }

  EpisodeTargetOneOf1Builder get _$this {
    final $v = _$v;
    if ($v != null) {
      _kind = $v.kind;
      _name = $v.name;
      _number = $v.number;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EpisodeTargetOneOf1 other) {
    _$v = other as _$EpisodeTargetOneOf1;
  }

  @override
  void update(void Function(EpisodeTargetOneOf1Builder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EpisodeTargetOneOf1 build() => _build();

  _$EpisodeTargetOneOf1 _build() {
    final _$result = _$v ??
        _$EpisodeTargetOneOf1._(
          kind: BuiltValueNullFieldError.checkNotNull(
              kind, r'EpisodeTargetOneOf1', 'kind'),
          name: name,
          number: BuiltValueNullFieldError.checkNotNull(
              number, r'EpisodeTargetOneOf1', 'number'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
