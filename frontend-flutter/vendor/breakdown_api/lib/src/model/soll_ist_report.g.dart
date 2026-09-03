// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'soll_ist_report.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SollIstReport extends SollIstReport {
  @override
  final bool isFinal;
  @override
  final BuiltList<SollIstDiffRow> rows;

  factory _$SollIstReport([void Function(SollIstReportBuilder)? updates]) =>
      (SollIstReportBuilder()..update(updates))._build();

  _$SollIstReport._({required this.isFinal, required this.rows}) : super._();
  @override
  SollIstReport rebuild(void Function(SollIstReportBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SollIstReportBuilder toBuilder() => SollIstReportBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SollIstReport &&
        isFinal == other.isFinal &&
        rows == other.rows;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, isFinal.hashCode);
    _$hash = $jc(_$hash, rows.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SollIstReport')
          ..add('isFinal', isFinal)
          ..add('rows', rows))
        .toString();
  }
}

class SollIstReportBuilder
    implements Builder<SollIstReport, SollIstReportBuilder> {
  _$SollIstReport? _$v;

  bool? _isFinal;
  bool? get isFinal => _$this._isFinal;
  set isFinal(bool? isFinal) => _$this._isFinal = isFinal;

  ListBuilder<SollIstDiffRow>? _rows;
  ListBuilder<SollIstDiffRow> get rows =>
      _$this._rows ??= ListBuilder<SollIstDiffRow>();
  set rows(ListBuilder<SollIstDiffRow>? rows) => _$this._rows = rows;

  SollIstReportBuilder() {
    SollIstReport._defaults(this);
  }

  SollIstReportBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _isFinal = $v.isFinal;
      _rows = $v.rows.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SollIstReport other) {
    _$v = other as _$SollIstReport;
  }

  @override
  void update(void Function(SollIstReportBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SollIstReport build() => _build();

  _$SollIstReport _build() {
    _$SollIstReport _$result;
    try {
      _$result = _$v ??
          _$SollIstReport._(
            isFinal: BuiltValueNullFieldError.checkNotNull(
                isFinal, r'SollIstReport', 'isFinal'),
            rows: rows.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'rows';
        rows.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SollIstReport', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
