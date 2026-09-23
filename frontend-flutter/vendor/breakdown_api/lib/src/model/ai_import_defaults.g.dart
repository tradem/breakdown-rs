// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ai_import_defaults.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$AiImportDefaults extends AiImportDefaults {
  @override
  final String schedule;
  @override
  final String script;

  factory _$AiImportDefaults(
          [void Function(AiImportDefaultsBuilder)? updates]) =>
      (AiImportDefaultsBuilder()..update(updates))._build();

  _$AiImportDefaults._({required this.schedule, required this.script})
      : super._();
  @override
  AiImportDefaults rebuild(void Function(AiImportDefaultsBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  AiImportDefaultsBuilder toBuilder() =>
      AiImportDefaultsBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is AiImportDefaults &&
        schedule == other.schedule &&
        script == other.script;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, schedule.hashCode);
    _$hash = $jc(_$hash, script.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'AiImportDefaults')
          ..add('schedule', schedule)
          ..add('script', script))
        .toString();
  }
}

class AiImportDefaultsBuilder
    implements Builder<AiImportDefaults, AiImportDefaultsBuilder> {
  _$AiImportDefaults? _$v;

  String? _schedule;
  String? get schedule => _$this._schedule;
  set schedule(String? schedule) => _$this._schedule = schedule;

  String? _script;
  String? get script => _$this._script;
  set script(String? script) => _$this._script = script;

  AiImportDefaultsBuilder() {
    AiImportDefaults._defaults(this);
  }

  AiImportDefaultsBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _schedule = $v.schedule;
      _script = $v.script;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(AiImportDefaults other) {
    _$v = other as _$AiImportDefaults;
  }

  @override
  void update(void Function(AiImportDefaultsBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  AiImportDefaults build() => _build();

  _$AiImportDefaults _build() {
    final _$result = _$v ??
        _$AiImportDefaults._(
          schedule: BuiltValueNullFieldError.checkNotNull(
              schedule, r'AiImportDefaults', 'schedule'),
          script: BuiltValueNullFieldError.checkNotNull(
              script, r'AiImportDefaults', 'script'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
