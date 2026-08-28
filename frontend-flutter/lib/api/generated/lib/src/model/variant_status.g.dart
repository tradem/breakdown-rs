// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'variant_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const VariantStatus _$pending = const VariantStatus._('pending');
const VariantStatus _$ready = const VariantStatus._('ready');
const VariantStatus _$failed = const VariantStatus._('failed');

VariantStatus _$valueOf(String name) {
  switch (name) {
    case 'pending':
      return _$pending;
    case 'ready':
      return _$ready;
    case 'failed':
      return _$failed;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<VariantStatus> _$values =
    BuiltSet<VariantStatus>(const <VariantStatus>[
  _$pending,
  _$ready,
  _$failed,
]);

class _$VariantStatusMeta {
  const _$VariantStatusMeta();
  VariantStatus get pending => _$pending;
  VariantStatus get ready => _$ready;
  VariantStatus get failed => _$failed;
  VariantStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<VariantStatus> get values => _$values;
}

abstract class _$VariantStatusMixin {
  // ignore: non_constant_identifier_names
  _$VariantStatusMeta get VariantStatus => const _$VariantStatusMeta();
}

Serializer<VariantStatus> _$variantStatusSerializer =
    _$VariantStatusSerializer();

class _$VariantStatusSerializer implements PrimitiveSerializer<VariantStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'pending': 'Pending',
    'ready': 'Ready',
    'failed': 'Failed',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'Pending': 'pending',
    'Ready': 'ready',
    'Failed': 'failed',
  };

  @override
  final Iterable<Type> types = const <Type>[VariantStatus];
  @override
  final String wireName = 'VariantStatus';

  @override
  Object serialize(Serializers serializers, VariantStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  VariantStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      VariantStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
