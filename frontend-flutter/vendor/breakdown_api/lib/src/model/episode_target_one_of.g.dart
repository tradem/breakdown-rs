// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'episode_target_one_of.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const EpisodeTargetOneOfKindEnum _$episodeTargetOneOfKindEnum_existing =
    const EpisodeTargetOneOfKindEnum._('existing');

EpisodeTargetOneOfKindEnum _$episodeTargetOneOfKindEnumValueOf(String name) {
  switch (name) {
    case 'existing':
      return _$episodeTargetOneOfKindEnum_existing;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<EpisodeTargetOneOfKindEnum> _$episodeTargetOneOfKindEnumValues =
    BuiltSet<EpisodeTargetOneOfKindEnum>(const <EpisodeTargetOneOfKindEnum>[
  _$episodeTargetOneOfKindEnum_existing,
]);

Serializer<EpisodeTargetOneOfKindEnum> _$episodeTargetOneOfKindEnumSerializer =
    _$EpisodeTargetOneOfKindEnumSerializer();

class _$EpisodeTargetOneOfKindEnumSerializer
    implements PrimitiveSerializer<EpisodeTargetOneOfKindEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'existing': 'existing',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'existing': 'existing',
  };

  @override
  final Iterable<Type> types = const <Type>[EpisodeTargetOneOfKindEnum];
  @override
  final String wireName = 'EpisodeTargetOneOfKindEnum';

  @override
  Object serialize(Serializers serializers, EpisodeTargetOneOfKindEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  EpisodeTargetOneOfKindEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      EpisodeTargetOneOfKindEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$EpisodeTargetOneOf extends EpisodeTargetOneOf {
  @override
  final String episodeId;
  @override
  final EpisodeTargetOneOfKindEnum kind;

  factory _$EpisodeTargetOneOf(
          [void Function(EpisodeTargetOneOfBuilder)? updates]) =>
      (EpisodeTargetOneOfBuilder()..update(updates))._build();

  _$EpisodeTargetOneOf._({required this.episodeId, required this.kind})
      : super._();
  @override
  EpisodeTargetOneOf rebuild(
          void Function(EpisodeTargetOneOfBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EpisodeTargetOneOfBuilder toBuilder() =>
      EpisodeTargetOneOfBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EpisodeTargetOneOf &&
        episodeId == other.episodeId &&
        kind == other.kind;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, episodeId.hashCode);
    _$hash = $jc(_$hash, kind.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EpisodeTargetOneOf')
          ..add('episodeId', episodeId)
          ..add('kind', kind))
        .toString();
  }
}

class EpisodeTargetOneOfBuilder
    implements Builder<EpisodeTargetOneOf, EpisodeTargetOneOfBuilder> {
  _$EpisodeTargetOneOf? _$v;

  String? _episodeId;
  String? get episodeId => _$this._episodeId;
  set episodeId(String? episodeId) => _$this._episodeId = episodeId;

  EpisodeTargetOneOfKindEnum? _kind;
  EpisodeTargetOneOfKindEnum? get kind => _$this._kind;
  set kind(EpisodeTargetOneOfKindEnum? kind) => _$this._kind = kind;

  EpisodeTargetOneOfBuilder() {
    EpisodeTargetOneOf._defaults(this);
  }

  EpisodeTargetOneOfBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _episodeId = $v.episodeId;
      _kind = $v.kind;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EpisodeTargetOneOf other) {
    _$v = other as _$EpisodeTargetOneOf;
  }

  @override
  void update(void Function(EpisodeTargetOneOfBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EpisodeTargetOneOf build() => _build();

  _$EpisodeTargetOneOf _build() {
    final _$result = _$v ??
        _$EpisodeTargetOneOf._(
          episodeId: BuiltValueNullFieldError.checkNotNull(
              episodeId, r'EpisodeTargetOneOf', 'episodeId'),
          kind: BuiltValueNullFieldError.checkNotNull(
              kind, r'EpisodeTargetOneOf', 'kind'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
