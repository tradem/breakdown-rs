// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'document_kind.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const DocumentKind _$script = const DocumentKind._('script');
const DocumentKind _$schedule = const DocumentKind._('schedule');

DocumentKind _$valueOf(String name) {
  switch (name) {
    case 'script':
      return _$script;
    case 'schedule':
      return _$schedule;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<DocumentKind> _$values =
    BuiltSet<DocumentKind>(const <DocumentKind>[
  _$script,
  _$schedule,
]);

class _$DocumentKindMeta {
  const _$DocumentKindMeta();
  DocumentKind get script => _$script;
  DocumentKind get schedule => _$schedule;
  DocumentKind valueOf(String name) => _$valueOf(name);
  BuiltSet<DocumentKind> get values => _$values;
}

abstract class _$DocumentKindMixin {
  // ignore: non_constant_identifier_names
  _$DocumentKindMeta get DocumentKind => const _$DocumentKindMeta();
}

Serializer<DocumentKind> _$documentKindSerializer = _$DocumentKindSerializer();

class _$DocumentKindSerializer implements PrimitiveSerializer<DocumentKind> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'script': 'script',
    'schedule': 'schedule',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'script': 'script',
    'schedule': 'schedule',
  };

  @override
  final Iterable<Type> types = const <Type>[DocumentKind];
  @override
  final String wireName = 'DocumentKind';

  @override
  Object serialize(Serializers serializers, DocumentKind object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  DocumentKind deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      DocumentKind.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
