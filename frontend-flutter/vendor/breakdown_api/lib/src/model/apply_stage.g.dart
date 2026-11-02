// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'apply_stage.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const ApplyStage _$applying = const ApplyStage._('applying');
const ApplyStage _$finalizing = const ApplyStage._('finalizing');

ApplyStage _$valueOf(String name) {
  switch (name) {
    case 'applying':
      return _$applying;
    case 'finalizing':
      return _$finalizing;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<ApplyStage> _$values = BuiltSet<ApplyStage>(const <ApplyStage>[
  _$applying,
  _$finalizing,
]);

class _$ApplyStageMeta {
  const _$ApplyStageMeta();
  ApplyStage get applying => _$applying;
  ApplyStage get finalizing => _$finalizing;
  ApplyStage valueOf(String name) => _$valueOf(name);
  BuiltSet<ApplyStage> get values => _$values;
}

abstract class _$ApplyStageMixin {
  // ignore: non_constant_identifier_names
  _$ApplyStageMeta get ApplyStage => const _$ApplyStageMeta();
}

Serializer<ApplyStage> _$applyStageSerializer = _$ApplyStageSerializer();

class _$ApplyStageSerializer implements PrimitiveSerializer<ApplyStage> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'applying': 'applying',
    'finalizing': 'finalizing',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'applying': 'applying',
    'finalizing': 'finalizing',
  };

  @override
  final Iterable<Type> types = const <Type>[ApplyStage];
  @override
  final String wireName = 'ApplyStage';

  @override
  Object serialize(Serializers serializers, ApplyStage object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  ApplyStage deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      ApplyStage.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
