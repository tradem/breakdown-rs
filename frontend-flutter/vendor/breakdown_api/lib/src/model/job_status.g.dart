// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job_status.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const JobStatus _$pending = const JobStatus._('pending');
const JobStatus _$running = const JobStatus._('running');
const JobStatus _$succeeded = const JobStatus._('succeeded');
const JobStatus _$failed = const JobStatus._('failed');
const JobStatus _$deadLetter = const JobStatus._('deadLetter');
const JobStatus _$payloadUnavailable = const JobStatus._('payloadUnavailable');

JobStatus _$valueOf(String name) {
  switch (name) {
    case 'pending':
      return _$pending;
    case 'running':
      return _$running;
    case 'succeeded':
      return _$succeeded;
    case 'failed':
      return _$failed;
    case 'deadLetter':
      return _$deadLetter;
    case 'payloadUnavailable':
      return _$payloadUnavailable;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<JobStatus> _$values = BuiltSet<JobStatus>(const <JobStatus>[
  _$pending,
  _$running,
  _$succeeded,
  _$failed,
  _$deadLetter,
  _$payloadUnavailable,
]);

class _$JobStatusMeta {
  const _$JobStatusMeta();
  JobStatus get pending => _$pending;
  JobStatus get running => _$running;
  JobStatus get succeeded => _$succeeded;
  JobStatus get failed => _$failed;
  JobStatus get deadLetter => _$deadLetter;
  JobStatus get payloadUnavailable => _$payloadUnavailable;
  JobStatus valueOf(String name) => _$valueOf(name);
  BuiltSet<JobStatus> get values => _$values;
}

abstract class _$JobStatusMixin {
  // ignore: non_constant_identifier_names
  _$JobStatusMeta get JobStatus => const _$JobStatusMeta();
}

Serializer<JobStatus> _$jobStatusSerializer = _$JobStatusSerializer();

class _$JobStatusSerializer implements PrimitiveSerializer<JobStatus> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'pending': 'pending',
    'running': 'running',
    'succeeded': 'succeeded',
    'failed': 'failed',
    'deadLetter': 'dead_letter',
    'payloadUnavailable': 'payload_unavailable',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'pending': 'pending',
    'running': 'running',
    'succeeded': 'succeeded',
    'failed': 'failed',
    'dead_letter': 'deadLetter',
    'payload_unavailable': 'payloadUnavailable',
  };

  @override
  final Iterable<Type> types = const <Type>[JobStatus];
  @override
  final String wireName = 'JobStatus';

  @override
  Object serialize(Serializers serializers, JobStatus object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  JobStatus deserialize(Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      JobStatus.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
