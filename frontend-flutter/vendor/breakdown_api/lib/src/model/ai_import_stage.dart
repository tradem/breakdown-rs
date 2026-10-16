// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'ai_import_stage.g.dart';

/// The extraction stage an AI import job is currently in (issue #664).  Surfaces *where* in the pipeline a running job is, so the client can show something more informative than an indeterminate spinner. Never per-LLM- token — it only advances at stage boundaries and completed chunks.
class AiImportStage extends EnumClass {
  @BuiltValueEnumConst(wireName: r'extracting_text')
  static const AiImportStage extractingText = _$extractingText;
  @BuiltValueEnumConst(wireName: r'extracting')
  static const AiImportStage extracting = _$extracting;
  @BuiltValueEnumConst(wireName: r'merging')
  static const AiImportStage merging = _$merging;
  @BuiltValueEnumConst(wireName: r'storing_preview')
  static const AiImportStage storingPreview = _$storingPreview;

  static Serializer<AiImportStage> get serializer => _$aiImportStageSerializer;

  const AiImportStage._(String name) : super(name);

  static BuiltSet<AiImportStage> get values => _$values;
  static AiImportStage valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class AiImportStageMixin = Object with _$AiImportStageMixin;
