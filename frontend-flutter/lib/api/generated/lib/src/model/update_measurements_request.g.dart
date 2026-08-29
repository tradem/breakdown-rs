// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_measurements_request.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$UpdateMeasurementsRequest extends UpdateMeasurementsRequest {
  @override
  final CharacterMeasurements measurements;
  @override
  final int version;

  factory _$UpdateMeasurementsRequest(
          [void Function(UpdateMeasurementsRequestBuilder)? updates]) =>
      (UpdateMeasurementsRequestBuilder()..update(updates))._build();

  _$UpdateMeasurementsRequest._(
      {required this.measurements, required this.version})
      : super._();
  @override
  UpdateMeasurementsRequest rebuild(
          void Function(UpdateMeasurementsRequestBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  UpdateMeasurementsRequestBuilder toBuilder() =>
      UpdateMeasurementsRequestBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is UpdateMeasurementsRequest &&
        measurements == other.measurements &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, measurements.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'UpdateMeasurementsRequest')
          ..add('measurements', measurements)
          ..add('version', version))
        .toString();
  }
}

class UpdateMeasurementsRequestBuilder
    implements
        Builder<UpdateMeasurementsRequest, UpdateMeasurementsRequestBuilder> {
  _$UpdateMeasurementsRequest? _$v;

  CharacterMeasurementsBuilder? _measurements;
  CharacterMeasurementsBuilder get measurements =>
      _$this._measurements ??= CharacterMeasurementsBuilder();
  set measurements(CharacterMeasurementsBuilder? measurements) =>
      _$this._measurements = measurements;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  UpdateMeasurementsRequestBuilder() {
    UpdateMeasurementsRequest._defaults(this);
  }

  UpdateMeasurementsRequestBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _measurements = $v.measurements.toBuilder();
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(UpdateMeasurementsRequest other) {
    _$v = other as _$UpdateMeasurementsRequest;
  }

  @override
  void update(void Function(UpdateMeasurementsRequestBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  UpdateMeasurementsRequest build() => _build();

  _$UpdateMeasurementsRequest _build() {
    _$UpdateMeasurementsRequest _$result;
    try {
      _$result = _$v ??
          _$UpdateMeasurementsRequest._(
            measurements: measurements.build(),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'UpdateMeasurementsRequest', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'measurements';
        measurements.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'UpdateMeasurementsRequest', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
