// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'series_membership_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SeriesMembershipDto extends SeriesMembershipDto {
  @override
  final BuiltList<String> capabilities;
  @override
  final bool hasActiveCostumeRoleInSeries;
  @override
  final String projectId;

  factory _$SeriesMembershipDto(
          [void Function(SeriesMembershipDtoBuilder)? updates]) =>
      (SeriesMembershipDtoBuilder()..update(updates))._build();

  _$SeriesMembershipDto._(
      {required this.capabilities,
      required this.hasActiveCostumeRoleInSeries,
      required this.projectId})
      : super._();
  @override
  SeriesMembershipDto rebuild(
          void Function(SeriesMembershipDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SeriesMembershipDtoBuilder toBuilder() =>
      SeriesMembershipDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SeriesMembershipDto &&
        capabilities == other.capabilities &&
        hasActiveCostumeRoleInSeries == other.hasActiveCostumeRoleInSeries &&
        projectId == other.projectId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, capabilities.hashCode);
    _$hash = $jc(_$hash, hasActiveCostumeRoleInSeries.hashCode);
    _$hash = $jc(_$hash, projectId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SeriesMembershipDto')
          ..add('capabilities', capabilities)
          ..add('hasActiveCostumeRoleInSeries', hasActiveCostumeRoleInSeries)
          ..add('projectId', projectId))
        .toString();
  }
}

class SeriesMembershipDtoBuilder
    implements Builder<SeriesMembershipDto, SeriesMembershipDtoBuilder> {
  _$SeriesMembershipDto? _$v;

  ListBuilder<String>? _capabilities;
  ListBuilder<String> get capabilities =>
      _$this._capabilities ??= ListBuilder<String>();
  set capabilities(ListBuilder<String>? capabilities) =>
      _$this._capabilities = capabilities;

  bool? _hasActiveCostumeRoleInSeries;
  bool? get hasActiveCostumeRoleInSeries =>
      _$this._hasActiveCostumeRoleInSeries;
  set hasActiveCostumeRoleInSeries(bool? hasActiveCostumeRoleInSeries) =>
      _$this._hasActiveCostumeRoleInSeries = hasActiveCostumeRoleInSeries;

  String? _projectId;
  String? get projectId => _$this._projectId;
  set projectId(String? projectId) => _$this._projectId = projectId;

  SeriesMembershipDtoBuilder() {
    SeriesMembershipDto._defaults(this);
  }

  SeriesMembershipDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _capabilities = $v.capabilities.toBuilder();
      _hasActiveCostumeRoleInSeries = $v.hasActiveCostumeRoleInSeries;
      _projectId = $v.projectId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SeriesMembershipDto other) {
    _$v = other as _$SeriesMembershipDto;
  }

  @override
  void update(void Function(SeriesMembershipDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SeriesMembershipDto build() => _build();

  _$SeriesMembershipDto _build() {
    _$SeriesMembershipDto _$result;
    try {
      _$result = _$v ??
          _$SeriesMembershipDto._(
            capabilities: capabilities.build(),
            hasActiveCostumeRoleInSeries: BuiltValueNullFieldError.checkNotNull(
                hasActiveCostumeRoleInSeries,
                r'SeriesMembershipDto',
                'hasActiveCostumeRoleInSeries'),
            projectId: BuiltValueNullFieldError.checkNotNull(
                projectId, r'SeriesMembershipDto', 'projectId'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'capabilities';
        capabilities.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SeriesMembershipDto', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
