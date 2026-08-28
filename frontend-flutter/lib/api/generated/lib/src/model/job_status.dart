// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'job_status.g.dart';

/// Operational lifecycle of an AI import job.  `Failed` is the *retryable* state (a due `next_attempt_at` makes the job claimable again); `DeadLetter` and `PayloadUnavailable` are terminal.
class JobStatus extends EnumClass {
  @BuiltValueEnumConst(wireName: r'pending')
  static const JobStatus pending = _$pending;
  @BuiltValueEnumConst(wireName: r'running')
  static const JobStatus running = _$running;
  @BuiltValueEnumConst(wireName: r'succeeded')
  static const JobStatus succeeded = _$succeeded;
  @BuiltValueEnumConst(wireName: r'failed')
  static const JobStatus failed = _$failed;
  @BuiltValueEnumConst(wireName: r'dead_letter')
  static const JobStatus deadLetter = _$deadLetter;
  @BuiltValueEnumConst(wireName: r'payload_unavailable')
  static const JobStatus payloadUnavailable = _$payloadUnavailable;

  static Serializer<JobStatus> get serializer => _$jobStatusSerializer;

  const JobStatus._(String name) : super(name);

  static BuiltSet<JobStatus> get values => _$values;
  static JobStatus valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class JobStatusMixin = Object with _$JobStatusMixin;
