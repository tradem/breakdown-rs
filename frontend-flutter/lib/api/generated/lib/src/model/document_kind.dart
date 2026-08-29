// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'document_kind.g.dart';

/// The two document kinds supported by the import pipeline.
class DocumentKind extends EnumClass {
  @BuiltValueEnumConst(wireName: r'script')
  static const DocumentKind script = _$script;
  @BuiltValueEnumConst(wireName: r'schedule')
  static const DocumentKind schedule = _$schedule;

  static Serializer<DocumentKind> get serializer => _$documentKindSerializer;

  const DocumentKind._(String name) : super(name);

  static BuiltSet<DocumentKind> get values => _$values;
  static DocumentKind valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class DocumentKindMixin = Object with _$DocumentKindMixin;
