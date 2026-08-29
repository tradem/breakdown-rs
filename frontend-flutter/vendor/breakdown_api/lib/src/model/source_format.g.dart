// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_format.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const SourceFormat _$csv = const SourceFormat._('csv');
const SourceFormat _$pdf = const SourceFormat._('pdf');
const SourceFormat _$plainText = const SourceFormat._('plainText');

SourceFormat _$valueOf(String name) {
  switch (name) {
    case 'csv':
      return _$csv;
    case 'pdf':
      return _$pdf;
    case 'plainText':
      return _$plainText;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<SourceFormat> _$values =
    BuiltSet<SourceFormat>(const <SourceFormat>[
  _$csv,
  _$pdf,
  _$plainText,
]);

class _$SourceFormatMeta {
  const _$SourceFormatMeta();
  SourceFormat get csv => _$csv;
  SourceFormat get pdf => _$pdf;
  SourceFormat get plainText => _$plainText;
  SourceFormat valueOf(String name) => _$valueOf(name);
  BuiltSet<SourceFormat> get values => _$values;
}

abstract class _$SourceFormatMixin {
  // ignore: non_constant_identifier_names
  _$SourceFormatMeta get SourceFormat => const _$SourceFormatMeta();
}

Serializer<SourceFormat> _$sourceFormatSerializer = _$SourceFormatSerializer();

class _$SourceFormatSerializer implements PrimitiveSerializer<SourceFormat> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'csv': 'csv',
    'pdf': 'pdf',
    'plainText': 'plain_text',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'csv': 'csv',
    'pdf': 'pdf',
    'plain_text': 'plainText',
  };

  @override
  final Iterable<Type> types = const <Type>[SourceFormat];
  @override
  final String wireName = 'SourceFormat';

  @override
  Object serialize(Serializers serializers, SourceFormat object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  SourceFormat deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      SourceFormat.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
