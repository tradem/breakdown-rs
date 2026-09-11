// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dead_letter_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DeadLetterEntry extends DeadLetterEntry {
  @override
  final int attempts;
  @override
  final String? constraintName;
  @override
  final String errorMessage;
  @override
  final String eventName;
  @override
  final DateTime firstSeenAt;
  @override
  final DateTime lastSeenAt;
  @override
  final int partitionId;
  @override
  final String projectionId;
  @override
  final int sequence;
  @override
  final String? sqlstate;
  @override
  final String streamId;

  factory _$DeadLetterEntry([void Function(DeadLetterEntryBuilder)? updates]) =>
      (DeadLetterEntryBuilder()..update(updates))._build();

  _$DeadLetterEntry._(
      {required this.attempts,
      this.constraintName,
      required this.errorMessage,
      required this.eventName,
      required this.firstSeenAt,
      required this.lastSeenAt,
      required this.partitionId,
      required this.projectionId,
      required this.sequence,
      this.sqlstate,
      required this.streamId})
      : super._();
  @override
  DeadLetterEntry rebuild(void Function(DeadLetterEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DeadLetterEntryBuilder toBuilder() => DeadLetterEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DeadLetterEntry &&
        attempts == other.attempts &&
        constraintName == other.constraintName &&
        errorMessage == other.errorMessage &&
        eventName == other.eventName &&
        firstSeenAt == other.firstSeenAt &&
        lastSeenAt == other.lastSeenAt &&
        partitionId == other.partitionId &&
        projectionId == other.projectionId &&
        sequence == other.sequence &&
        sqlstate == other.sqlstate &&
        streamId == other.streamId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, attempts.hashCode);
    _$hash = $jc(_$hash, constraintName.hashCode);
    _$hash = $jc(_$hash, errorMessage.hashCode);
    _$hash = $jc(_$hash, eventName.hashCode);
    _$hash = $jc(_$hash, firstSeenAt.hashCode);
    _$hash = $jc(_$hash, lastSeenAt.hashCode);
    _$hash = $jc(_$hash, partitionId.hashCode);
    _$hash = $jc(_$hash, projectionId.hashCode);
    _$hash = $jc(_$hash, sequence.hashCode);
    _$hash = $jc(_$hash, sqlstate.hashCode);
    _$hash = $jc(_$hash, streamId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DeadLetterEntry')
          ..add('attempts', attempts)
          ..add('constraintName', constraintName)
          ..add('errorMessage', errorMessage)
          ..add('eventName', eventName)
          ..add('firstSeenAt', firstSeenAt)
          ..add('lastSeenAt', lastSeenAt)
          ..add('partitionId', partitionId)
          ..add('projectionId', projectionId)
          ..add('sequence', sequence)
          ..add('sqlstate', sqlstate)
          ..add('streamId', streamId))
        .toString();
  }
}

class DeadLetterEntryBuilder
    implements Builder<DeadLetterEntry, DeadLetterEntryBuilder> {
  _$DeadLetterEntry? _$v;

  int? _attempts;
  int? get attempts => _$this._attempts;
  set attempts(int? attempts) => _$this._attempts = attempts;

  String? _constraintName;
  String? get constraintName => _$this._constraintName;
  set constraintName(String? constraintName) =>
      _$this._constraintName = constraintName;

  String? _errorMessage;
  String? get errorMessage => _$this._errorMessage;
  set errorMessage(String? errorMessage) => _$this._errorMessage = errorMessage;

  String? _eventName;
  String? get eventName => _$this._eventName;
  set eventName(String? eventName) => _$this._eventName = eventName;

  DateTime? _firstSeenAt;
  DateTime? get firstSeenAt => _$this._firstSeenAt;
  set firstSeenAt(DateTime? firstSeenAt) => _$this._firstSeenAt = firstSeenAt;

  DateTime? _lastSeenAt;
  DateTime? get lastSeenAt => _$this._lastSeenAt;
  set lastSeenAt(DateTime? lastSeenAt) => _$this._lastSeenAt = lastSeenAt;

  int? _partitionId;
  int? get partitionId => _$this._partitionId;
  set partitionId(int? partitionId) => _$this._partitionId = partitionId;

  String? _projectionId;
  String? get projectionId => _$this._projectionId;
  set projectionId(String? projectionId) => _$this._projectionId = projectionId;

  int? _sequence;
  int? get sequence => _$this._sequence;
  set sequence(int? sequence) => _$this._sequence = sequence;

  String? _sqlstate;
  String? get sqlstate => _$this._sqlstate;
  set sqlstate(String? sqlstate) => _$this._sqlstate = sqlstate;

  String? _streamId;
  String? get streamId => _$this._streamId;
  set streamId(String? streamId) => _$this._streamId = streamId;

  DeadLetterEntryBuilder() {
    DeadLetterEntry._defaults(this);
  }

  DeadLetterEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _attempts = $v.attempts;
      _constraintName = $v.constraintName;
      _errorMessage = $v.errorMessage;
      _eventName = $v.eventName;
      _firstSeenAt = $v.firstSeenAt;
      _lastSeenAt = $v.lastSeenAt;
      _partitionId = $v.partitionId;
      _projectionId = $v.projectionId;
      _sequence = $v.sequence;
      _sqlstate = $v.sqlstate;
      _streamId = $v.streamId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DeadLetterEntry other) {
    _$v = other as _$DeadLetterEntry;
  }

  @override
  void update(void Function(DeadLetterEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DeadLetterEntry build() => _build();

  _$DeadLetterEntry _build() {
    final _$result = _$v ??
        _$DeadLetterEntry._(
          attempts: BuiltValueNullFieldError.checkNotNull(
              attempts, r'DeadLetterEntry', 'attempts'),
          constraintName: constraintName,
          errorMessage: BuiltValueNullFieldError.checkNotNull(
              errorMessage, r'DeadLetterEntry', 'errorMessage'),
          eventName: BuiltValueNullFieldError.checkNotNull(
              eventName, r'DeadLetterEntry', 'eventName'),
          firstSeenAt: BuiltValueNullFieldError.checkNotNull(
              firstSeenAt, r'DeadLetterEntry', 'firstSeenAt'),
          lastSeenAt: BuiltValueNullFieldError.checkNotNull(
              lastSeenAt, r'DeadLetterEntry', 'lastSeenAt'),
          partitionId: BuiltValueNullFieldError.checkNotNull(
              partitionId, r'DeadLetterEntry', 'partitionId'),
          projectionId: BuiltValueNullFieldError.checkNotNull(
              projectionId, r'DeadLetterEntry', 'projectionId'),
          sequence: BuiltValueNullFieldError.checkNotNull(
              sequence, r'DeadLetterEntry', 'sequence'),
          sqlstate: sqlstate,
          streamId: BuiltValueNullFieldError.checkNotNull(
              streamId, r'DeadLetterEntry', 'streamId'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
