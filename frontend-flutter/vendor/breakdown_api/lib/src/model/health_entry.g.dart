// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthEntry extends HealthEntry {
  @override
  final String? description;
  @override
  final int durationMs;
  @override
  final HealthStatus status;
  @override
  final BuiltList<String> tags;

  factory _$HealthEntry([void Function(HealthEntryBuilder)? updates]) =>
      (HealthEntryBuilder()..update(updates))._build();

  _$HealthEntry._(
      {this.description,
      required this.durationMs,
      required this.status,
      required this.tags})
      : super._();
  @override
  HealthEntry rebuild(void Function(HealthEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthEntryBuilder toBuilder() => HealthEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthEntry &&
        description == other.description &&
        durationMs == other.durationMs &&
        status == other.status &&
        tags == other.tags;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, durationMs.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, tags.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthEntry')
          ..add('description', description)
          ..add('durationMs', durationMs)
          ..add('status', status)
          ..add('tags', tags))
        .toString();
  }
}

class HealthEntryBuilder implements Builder<HealthEntry, HealthEntryBuilder> {
  _$HealthEntry? _$v;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  int? _durationMs;
  int? get durationMs => _$this._durationMs;
  set durationMs(int? durationMs) => _$this._durationMs = durationMs;

  HealthStatus? _status;
  HealthStatus? get status => _$this._status;
  set status(HealthStatus? status) => _$this._status = status;

  ListBuilder<String>? _tags;
  ListBuilder<String> get tags => _$this._tags ??= ListBuilder<String>();
  set tags(ListBuilder<String>? tags) => _$this._tags = tags;

  HealthEntryBuilder() {
    HealthEntry._defaults(this);
  }

  HealthEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _description = $v.description;
      _durationMs = $v.durationMs;
      _status = $v.status;
      _tags = $v.tags.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthEntry other) {
    _$v = other as _$HealthEntry;
  }

  @override
  void update(void Function(HealthEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthEntry build() => _build();

  _$HealthEntry _build() {
    _$HealthEntry _$result;
    try {
      _$result = _$v ??
          _$HealthEntry._(
            description: description,
            durationMs: BuiltValueNullFieldError.checkNotNull(
                durationMs, r'HealthEntry', 'durationMs'),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'HealthEntry', 'status'),
            tags: tags.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'tags';
        tags.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'HealthEntry', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
