// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_stage.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const AiImportStage _$extractingText = const AiImportStage._('extractingText');
const AiImportStage _$extracting = const AiImportStage._('extracting');
const AiImportStage _$merging = const AiImportStage._('merging');
const AiImportStage _$storingPreview = const AiImportStage._('storingPreview');

AiImportStage _$valueOf(String name) {
  switch (name) {
    case 'extractingText':
      return _$extractingText;
    case 'extracting':
      return _$extracting;
    case 'merging':
      return _$merging;
    case 'storingPreview':
      return _$storingPreview;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<AiImportStage> _$values =
    BuiltSet<AiImportStage>(const <AiImportStage>[
  _$extractingText,
  _$extracting,
  _$merging,
  _$storingPreview,
]);

class _$AiImportStageMeta {
  const _$AiImportStageMeta();
  AiImportStage get extractingText => _$extractingText;
  AiImportStage get extracting => _$extracting;
  AiImportStage get merging => _$merging;
  AiImportStage get storingPreview => _$storingPreview;
  AiImportStage valueOf(String name) => _$valueOf(name);
  BuiltSet<AiImportStage> get values => _$values;
}

abstract class _$AiImportStageMixin {
  // ignore: non_constant_identifier_names
  _$AiImportStageMeta get AiImportStage => const _$AiImportStageMeta();
}

Serializer<AiImportStage> _$aiImportStageSerializer =
    _$AiImportStageSerializer();

class _$AiImportStageSerializer implements PrimitiveSerializer<AiImportStage> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'extractingText': 'extracting_text',
    'extracting': 'extracting',
    'merging': 'merging',
    'storingPreview': 'storing_preview',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'extracting_text': 'extractingText',
    'extracting': 'extracting',
    'merging': 'merging',
    'storing_preview': 'storingPreview',
  };

  @override
  final Iterable<Type> types = const <Type>[AiImportStage];
  @override
  final String wireName = 'AiImportStage';

  @override
  Object serialize(Serializers serializers, AiImportStage object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  AiImportStage deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      AiImportStage.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
