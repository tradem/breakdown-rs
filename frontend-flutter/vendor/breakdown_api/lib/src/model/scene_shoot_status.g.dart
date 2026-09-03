// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scene_shoot_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SceneShootStatus _$planned = const SceneShootStatus._('planned');
const SceneShootStatus _$scheduled = const SceneShootStatus._('scheduled');
const SceneShootStatus _$inProgress = const SceneShootStatus._('inProgress');
const SceneShootStatus _$shot = const SceneShootStatus._('shot');
const SceneShootStatus _$skipped = const SceneShootStatus._('skipped');

SceneShootStatus _$valueOf(String name) {
  switch (name) {
    case 'planned':
      return _$planned;
    case 'scheduled':
      return _$scheduled;
    case 'inProgress':
      return _$inProgress;
    case 'shot':
      return _$shot;
    case 'skipped':
      return _$skipped;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<SceneShootStatus> _$values =
    BuiltSet<SceneShootStatus>(const <SceneShootStatus>[
  _$planned,
  _$scheduled,
  _$inProgress,
  _$shot,
  _$skipped,
]);

class _$SceneShootStatusMeta {
  const _$SceneShootStatusMeta();
  SceneShootStatus get planned => _$planned;
  SceneShootStatus get scheduled => _$scheduled;
  SceneShootStatus get inProgress => _$inProgress;
  SceneShootStatus get shot => _$shot;
  SceneShootStatus get skipped => _$skipped;
  SceneShootStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<SceneShootStatus> get values => _$values;
}

abstract class _$SceneShootStatusMixin {
  // ignore: non_constant_identifier_names
  _$SceneShootStatusMeta get SceneShootStatus => const _$SceneShootStatusMeta();
}

Serializer<SceneShootStatus> _$sceneShootStatusSerializer =
    _$SceneShootStatusSerializer();

class _$SceneShootStatusSerializer
    implements PrimitiveSerializer<SceneShootStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'planned': 'Planned',
    'scheduled': 'Scheduled',
    'inProgress': 'InProgress',
    'shot': 'Shot',
    'skipped': 'Skipped',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'Planned': 'planned',
    'Scheduled': 'scheduled',
    'InProgress': 'inProgress',
    'Shot': 'shot',
    'Skipped': 'skipped',
  };

  @override
  final Iterable<Type> types = const <Type>[SceneShootStatus];
  @override
  final String wireName = 'SceneShootStatus';

  @override
  Object serialize(Serializers serializers, SceneShootStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  SceneShootStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      SceneShootStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
