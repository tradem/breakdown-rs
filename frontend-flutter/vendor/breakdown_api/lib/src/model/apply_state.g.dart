// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_state.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ApplyState _$idle = const ApplyState._('idle');
const ApplyState _$requested = const ApplyState._('requested');
const ApplyState _$running = const ApplyState._('running');
const ApplyState _$done = const ApplyState._('done');
const ApplyState _$failed = const ApplyState._('failed');

ApplyState _$valueOf(String name) {
  switch (name) {
    case 'idle':
      return _$idle;
    case 'requested':
      return _$requested;
    case 'running':
      return _$running;
    case 'done':
      return _$done;
    case 'failed':
      return _$failed;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ApplyState> _$values = BuiltSet<ApplyState>(const <ApplyState>[
  _$idle,
  _$requested,
  _$running,
  _$done,
  _$failed,
]);

class _$ApplyStateMeta {
  const _$ApplyStateMeta();
  ApplyState get idle => _$idle;
  ApplyState get requested => _$requested;
  ApplyState get running => _$running;
  ApplyState get done => _$done;
  ApplyState get failed => _$failed;
  ApplyState valueOf(String name) => _$valueOf(name);
  BuiltSet<ApplyState> get values => _$values;
}

abstract class _$ApplyStateMixin {
  // ignore: non_constant_identifier_names
  _$ApplyStateMeta get ApplyState => const _$ApplyStateMeta();
}

Serializer<ApplyState> _$applyStateSerializer = _$ApplyStateSerializer();

class _$ApplyStateSerializer implements PrimitiveSerializer<ApplyState> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'idle': 'idle',
    'requested': 'requested',
    'running': 'running',
    'done': 'done',
    'failed': 'failed',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'idle': 'idle',
    'requested': 'requested',
    'running': 'running',
    'done': 'done',
    'failed': 'failed',
  };

  @override
  final Iterable<Type> types = const <Type>[ApplyState];
  @override
  final String wireName = 'ApplyState';

  @override
  Object serialize(Serializers serializers, ApplyState object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ApplyState deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ApplyState.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
