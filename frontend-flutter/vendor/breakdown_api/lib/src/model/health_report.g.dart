// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'health_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$HealthReport extends HealthReport {
  @override
  final BuiltMap<String, HealthEntry> entries;
  @override
  final HealthStatus status;
  @override
  final int totalDurationMs;

  factory _$HealthReport([void Function(HealthReportBuilder)? updates]) =>
      (HealthReportBuilder()..update(updates))._build();

  _$HealthReport._(
      {required this.entries,
      required this.status,
      required this.totalDurationMs})
      : super._();
  @override
  HealthReport rebuild(void Function(HealthReportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  HealthReportBuilder toBuilder() => HealthReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is HealthReport &&
        entries == other.entries &&
        status == other.status &&
        totalDurationMs == other.totalDurationMs;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, entries.hashCode);
    _$hash = $jc(_$hash, status.hashCode);
    _$hash = $jc(_$hash, totalDurationMs.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'HealthReport')
          ..add('entries', entries)
          ..add('status', status)
          ..add('totalDurationMs', totalDurationMs))
        .toString();
  }
}

class HealthReportBuilder
    implements Builder<HealthReport, HealthReportBuilder> {
  _$HealthReport? _$v;

  MapBuilder<String, HealthEntry>? _entries;
  MapBuilder<String, HealthEntry> get entries =>
      _$this._entries ??= MapBuilder<String, HealthEntry>();
  set entries(MapBuilder<String, HealthEntry>? entries) =>
      _$this._entries = entries;

  HealthStatus? _status;
  HealthStatus? get status => _$this._status;
  set status(HealthStatus? status) => _$this._status = status;

  int? _totalDurationMs;
  int? get totalDurationMs => _$this._totalDurationMs;
  set totalDurationMs(int? totalDurationMs) =>
      _$this._totalDurationMs = totalDurationMs;

  HealthReportBuilder() {
    HealthReport._defaults(this);
  }

  HealthReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _entries = $v.entries.toBuilder();
      _status = $v.status;
      _totalDurationMs = $v.totalDurationMs;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(HealthReport other) {
    _$v = other as _$HealthReport;
  }

  @override
  void update(void Function(HealthReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  HealthReport build() => _build();

  _$HealthReport _build() {
    _$HealthReport _$result;
    try {
      _$result = _$v ??
          _$HealthReport._(
            entries: entries.build(),
            status: BuiltValueNullFieldError.checkNotNull(
                status, r'HealthReport', 'status'),
            totalDurationMs: BuiltValueNullFieldError.checkNotNull(
                totalDurationMs, r'HealthReport', 'totalDurationMs'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'entries';
        entries.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'HealthReport', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
