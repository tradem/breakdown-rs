// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'apply_state.g.dart';

/// Lifecycle state of one preview's **apply slot** (issue #899).  The apply used to have no durable state at all: \"requested\" was implicit in \"an HTTP request is in flight\", so a dropped connection erased the only trace that work had been asked for. This enum is that state — one slot per job, written only through the owner-fenced transitions of the queue port (`request_apply_run` → `mark_apply_running` → `complete_apply_run` / `fail_apply_run`).  It is deliberately **not** [`crate::ai::JobStatus`]: the job is terminal (`succeeded`) for the whole time an apply runs, because an apply is work done *on* a finished preview.
class ApplyState extends EnumClass {
  @BuiltValueEnumConst(wireName: r'idle')
  static const ApplyState idle = _$idle;
  @BuiltValueEnumConst(wireName: r'requested')
  static const ApplyState requested = _$requested;
  @BuiltValueEnumConst(wireName: r'running')
  static const ApplyState running = _$running;
  @BuiltValueEnumConst(wireName: r'done')
  static const ApplyState done = _$done;
  @BuiltValueEnumConst(wireName: r'failed')
  static const ApplyState failed = _$failed;

  static Serializer<ApplyState> get serializer => _$applyStateSerializer;

  const ApplyState._(String name) : super(name);

  static BuiltSet<ApplyState> get values => _$values;
  static ApplyState valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class ApplyStateMixin = Object with _$ApplyStateMixin;
