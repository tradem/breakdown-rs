// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'aggregate_soll_ist_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AggregateSollIstReport extends AggregateSollIstReport {
  @override
  final bool isFinal;
  @override
  final BuiltList<AggregateSollIstDiffRow> rows;
  @override
  final int totalShootingDays;
  @override
  final int wrappedShootingDays;

  factory _$AggregateSollIstReport(
          [void Function(AggregateSollIstReportBuilder)? updates]) =>
      (AggregateSollIstReportBuilder()..update(updates))._build();

  _$AggregateSollIstReport._(
      {required this.isFinal,
      required this.rows,
      required this.totalShootingDays,
      required this.wrappedShootingDays})
      : super._();
  @override
  AggregateSollIstReport rebuild(
          void Function(AggregateSollIstReportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AggregateSollIstReportBuilder toBuilder() =>
      AggregateSollIstReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AggregateSollIstReport &&
        isFinal == other.isFinal &&
        rows == other.rows &&
        totalShootingDays == other.totalShootingDays &&
        wrappedShootingDays == other.wrappedShootingDays;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, isFinal.hashCode);
    _$hash = $jc(_$hash, rows.hashCode);
    _$hash = $jc(_$hash, totalShootingDays.hashCode);
    _$hash = $jc(_$hash, wrappedShootingDays.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AggregateSollIstReport')
          ..add('isFinal', isFinal)
          ..add('rows', rows)
          ..add('totalShootingDays', totalShootingDays)
          ..add('wrappedShootingDays', wrappedShootingDays))
        .toString();
  }
}

class AggregateSollIstReportBuilder
    implements Builder<AggregateSollIstReport, AggregateSollIstReportBuilder> {
  _$AggregateSollIstReport? _$v;

  bool? _isFinal;
  bool? get isFinal => _$this._isFinal;
  set isFinal(bool? isFinal) => _$this._isFinal = isFinal;

  ListBuilder<AggregateSollIstDiffRow>? _rows;
  ListBuilder<AggregateSollIstDiffRow> get rows =>
      _$this._rows ??= ListBuilder<AggregateSollIstDiffRow>();
  set rows(ListBuilder<AggregateSollIstDiffRow>? rows) => _$this._rows = rows;

  int? _totalShootingDays;
  int? get totalShootingDays => _$this._totalShootingDays;
  set totalShootingDays(int? totalShootingDays) =>
      _$this._totalShootingDays = totalShootingDays;

  int? _wrappedShootingDays;
  int? get wrappedShootingDays => _$this._wrappedShootingDays;
  set wrappedShootingDays(int? wrappedShootingDays) =>
      _$this._wrappedShootingDays = wrappedShootingDays;

  AggregateSollIstReportBuilder() {
    AggregateSollIstReport._defaults(this);
  }

  AggregateSollIstReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _isFinal = $v.isFinal;
      _rows = $v.rows.toBuilder();
      _totalShootingDays = $v.totalShootingDays;
      _wrappedShootingDays = $v.wrappedShootingDays;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AggregateSollIstReport other) {
    _$v = other as _$AggregateSollIstReport;
  }

  @override
  void update(void Function(AggregateSollIstReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AggregateSollIstReport build() => _build();

  _$AggregateSollIstReport _build() {
    _$AggregateSollIstReport _$result;
    try {
      _$result = _$v ??
          _$AggregateSollIstReport._(
            isFinal: BuiltValueNullFieldError.checkNotNull(
                isFinal, r'AggregateSollIstReport', 'isFinal'),
            rows: rows.build(),
            totalShootingDays: BuiltValueNullFieldError.checkNotNull(
                totalShootingDays,
                r'AggregateSollIstReport',
                'totalShootingDays'),
            wrappedShootingDays: BuiltValueNullFieldError.checkNotNull(
                wrappedShootingDays,
                r'AggregateSollIstReport',
                'wrappedShootingDays'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rows';
        rows.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'AggregateSollIstReport', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
