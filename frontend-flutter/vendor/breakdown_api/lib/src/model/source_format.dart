// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'source_format.g.dart';

/// The declared format of an AI import source document, captured at the API edge from the upload's `Content-Type` and persisted on the job so the schedule worker can pick the extraction path without re-guessing the bytes (issue #221).  Only `Csv` is parsed natively; `Pdf` and `PlainText` are routed through the LLM extraction path. Scripts are always `Pdf`.
class SourceFormat extends EnumClass {
  @BuiltValueEnumConst(wireName: r'csv')
  static const SourceFormat csv = _$csv;
  @BuiltValueEnumConst(wireName: r'pdf')
  static const SourceFormat pdf = _$pdf;
  @BuiltValueEnumConst(wireName: r'plain_text')
  static const SourceFormat plainText = _$plainText;

  static Serializer<SourceFormat> get serializer => _$sourceFormatSerializer;

  const SourceFormat._(String name) : super(name);

  static BuiltSet<SourceFormat> get values => _$values;
  static SourceFormat valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class SourceFormatMixin = Object with _$SourceFormatMixin;
