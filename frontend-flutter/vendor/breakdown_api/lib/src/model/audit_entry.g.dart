// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'audit_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AuditEntry extends AuditEntry {
  @override
  final String? actor;
  @override
  final String? blockId;
  @override
  final String entityId;
  @override
  final String entityType;
  @override
  final String eventType;
  @override
  final String id;
  @override
  final DateTime occurredAt;
  @override
  final JsonObject? payload;
  @override
  final String? seriesId;

  factory _$AuditEntry([void Function(AuditEntryBuilder)? updates]) =>
      (AuditEntryBuilder()..update(updates))._build();

  _$AuditEntry._(
      {this.actor,
      this.blockId,
      required this.entityId,
      required this.entityType,
      required this.eventType,
      required this.id,
      required this.occurredAt,
      this.payload,
      this.seriesId})
      : super._();
  @override
  AuditEntry rebuild(void Function(AuditEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AuditEntryBuilder toBuilder() => AuditEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AuditEntry &&
        actor == other.actor &&
        blockId == other.blockId &&
        entityId == other.entityId &&
        entityType == other.entityType &&
        eventType == other.eventType &&
        id == other.id &&
        occurredAt == other.occurredAt &&
        payload == other.payload &&
        seriesId == other.seriesId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, actor.hashCode);
    _$hash = $jc(_$hash, blockId.hashCode);
    _$hash = $jc(_$hash, entityId.hashCode);
    _$hash = $jc(_$hash, entityType.hashCode);
    _$hash = $jc(_$hash, eventType.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, occurredAt.hashCode);
    _$hash = $jc(_$hash, payload.hashCode);
    _$hash = $jc(_$hash, seriesId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AuditEntry')
          ..add('actor', actor)
          ..add('blockId', blockId)
          ..add('entityId', entityId)
          ..add('entityType', entityType)
          ..add('eventType', eventType)
          ..add('id', id)
          ..add('occurredAt', occurredAt)
          ..add('payload', payload)
          ..add('seriesId', seriesId))
        .toString();
  }
}

class AuditEntryBuilder implements Builder<AuditEntry, AuditEntryBuilder> {
  _$AuditEntry? _$v;

  String? _actor;
  String? get actor => _$this._actor;
  set actor(String? actor) => _$this._actor = actor;

  String? _blockId;
  String? get blockId => _$this._blockId;
  set blockId(String? blockId) => _$this._blockId = blockId;

  String? _entityId;
  String? get entityId => _$this._entityId;
  set entityId(String? entityId) => _$this._entityId = entityId;

  String? _entityType;
  String? get entityType => _$this._entityType;
  set entityType(String? entityType) => _$this._entityType = entityType;

  String? _eventType;
  String? get eventType => _$this._eventType;
  set eventType(String? eventType) => _$this._eventType = eventType;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  DateTime? _occurredAt;
  DateTime? get occurredAt => _$this._occurredAt;
  set occurredAt(DateTime? occurredAt) => _$this._occurredAt = occurredAt;

  JsonObject? _payload;
  JsonObject? get payload => _$this._payload;
  set payload(JsonObject? payload) => _$this._payload = payload;

  String? _seriesId;
  String? get seriesId => _$this._seriesId;
  set seriesId(String? seriesId) => _$this._seriesId = seriesId;

  AuditEntryBuilder() {
    AuditEntry._defaults(this);
  }

  AuditEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _actor = $v.actor;
      _blockId = $v.blockId;
      _entityId = $v.entityId;
      _entityType = $v.entityType;
      _eventType = $v.eventType;
      _id = $v.id;
      _occurredAt = $v.occurredAt;
      _payload = $v.payload;
      _seriesId = $v.seriesId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AuditEntry other) {
    _$v = other as _$AuditEntry;
  }

  @override
  void update(void Function(AuditEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AuditEntry build() => _build();

  _$AuditEntry _build() {
    final _$result = _$v ??
        _$AuditEntry._(
          actor: actor,
          blockId: blockId,
          entityId: BuiltValueNullFieldError.checkNotNull(
              entityId, r'AuditEntry', 'entityId'),
          entityType: BuiltValueNullFieldError.checkNotNull(
              entityType, r'AuditEntry', 'entityType'),
          eventType: BuiltValueNullFieldError.checkNotNull(
              eventType, r'AuditEntry', 'eventType'),
          id: BuiltValueNullFieldError.checkNotNull(id, r'AuditEntry', 'id'),
          occurredAt: BuiltValueNullFieldError.checkNotNull(
              occurredAt, r'AuditEntry', 'occurredAt'),
          payload: payload,
          seriesId: seriesId,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
