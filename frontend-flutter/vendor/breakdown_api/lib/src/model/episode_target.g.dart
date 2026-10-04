// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_target.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EpisodeTargetKindEnum _$episodeTargetKindEnum_create =
    const EpisodeTargetKindEnum._('create');

EpisodeTargetKindEnum _$episodeTargetKindEnumValueOf(String name) {
  switch (name) {
    case 'create':
      return _$episodeTargetKindEnum_create;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<EpisodeTargetKindEnum> _$episodeTargetKindEnumValues =
    BuiltSet<EpisodeTargetKindEnum>(const <EpisodeTargetKindEnum>[
  _$episodeTargetKindEnum_create,
]);

Serializer<EpisodeTargetKindEnum> _$episodeTargetKindEnumSerializer =
    _$EpisodeTargetKindEnumSerializer();

class _$EpisodeTargetKindEnumSerializer
    implements PrimitiveSerializer<EpisodeTargetKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'create': 'create',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'create': 'create',
  };

  @override
  final Iterable<Type> types = const <Type>[EpisodeTargetKindEnum];
  @override
  final String wireName = 'EpisodeTargetKindEnum';

  @override
  Object serialize(Serializers serializers, EpisodeTargetKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  EpisodeTargetKindEnum deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      EpisodeTargetKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$EpisodeTarget extends EpisodeTarget {
  @override
  final OneOf oneOf;

  factory _$EpisodeTarget([void Function(EpisodeTargetBuilder)? updates]) =>
      (EpisodeTargetBuilder()..update(updates))._build();

  _$EpisodeTarget._({required this.oneOf}) : super._();
  @override
  EpisodeTarget rebuild(void Function(EpisodeTargetBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EpisodeTargetBuilder toBuilder() => EpisodeTargetBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EpisodeTarget && oneOf == other.oneOf;
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
    return (newBuiltValueToStringHelper(r'EpisodeTarget')..add('oneOf', oneOf))
        .toString();
  }
}

class EpisodeTargetBuilder
    implements Builder<EpisodeTarget, EpisodeTargetBuilder> {
  _$EpisodeTarget? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  EpisodeTargetBuilder() {
    EpisodeTarget._defaults(this);
  }

  EpisodeTargetBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EpisodeTarget other) {
    _$v = other as _$EpisodeTarget;
  }

  @override
  void update(void Function(EpisodeTargetBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EpisodeTarget build() => _build();

  _$EpisodeTarget _build() {
    final _$result = _$v ??
        _$EpisodeTarget._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'EpisodeTarget', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
