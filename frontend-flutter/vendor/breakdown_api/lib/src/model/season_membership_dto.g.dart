// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'season_membership_dto.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$SeasonMembershipDto extends SeasonMembershipDto {
  @override
  final BuiltList<String> capabilities;
  @override
  final bool hasActiveCostumeRoleInSeason;
  @override
  final String seasonId;

  factory _$SeasonMembershipDto(
          [void Function(SeasonMembershipDtoBuilder)? updates]) =>
      (SeasonMembershipDtoBuilder()..update(updates))._build();

  _$SeasonMembershipDto._(
      {required this.capabilities,
      required this.hasActiveCostumeRoleInSeason,
      required this.seasonId})
      : super._();
  @override
  SeasonMembershipDto rebuild(
          void Function(SeasonMembershipDtoBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  SeasonMembershipDtoBuilder toBuilder() =>
      SeasonMembershipDtoBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is SeasonMembershipDto &&
        capabilities == other.capabilities &&
        hasActiveCostumeRoleInSeason == other.hasActiveCostumeRoleInSeason &&
        seasonId == other.seasonId;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, capabilities.hashCode);
    _$hash = $jc(_$hash, hasActiveCostumeRoleInSeason.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'SeasonMembershipDto')
          ..add('capabilities', capabilities)
          ..add('hasActiveCostumeRoleInSeason', hasActiveCostumeRoleInSeason)
          ..add('seasonId', seasonId))
        .toString();
  }
}

class SeasonMembershipDtoBuilder
    implements Builder<SeasonMembershipDto, SeasonMembershipDtoBuilder> {
  _$SeasonMembershipDto? _$v;

  ListBuilder<String>? _capabilities;
  ListBuilder<String> get capabilities =>
      _$this._capabilities ??= ListBuilder<String>();
  set capabilities(ListBuilder<String>? capabilities) =>
      _$this._capabilities = capabilities;

  bool? _hasActiveCostumeRoleInSeason;
  bool? get hasActiveCostumeRoleInSeason =>
      _$this._hasActiveCostumeRoleInSeason;
  set hasActiveCostumeRoleInSeason(bool? hasActiveCostumeRoleInSeason) =>
      _$this._hasActiveCostumeRoleInSeason = hasActiveCostumeRoleInSeason;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  SeasonMembershipDtoBuilder() {
    SeasonMembershipDto._defaults(this);
  }

  SeasonMembershipDtoBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _capabilities = $v.capabilities.toBuilder();
      _hasActiveCostumeRoleInSeason = $v.hasActiveCostumeRoleInSeason;
      _seasonId = $v.seasonId;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(SeasonMembershipDto other) {
    _$v = other as _$SeasonMembershipDto;
  }

  @override
  void update(void Function(SeasonMembershipDtoBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  SeasonMembershipDto build() => _build();

  _$SeasonMembershipDto _build() {
    _$SeasonMembershipDto _$result;
    try {
      _$result = _$v ??
          _$SeasonMembershipDto._(
            capabilities: capabilities.build(),
            hasActiveCostumeRoleInSeason: BuiltValueNullFieldError.checkNotNull(
                hasActiveCostumeRoleInSeason,
                r'SeasonMembershipDto',
                'hasActiveCostumeRoleInSeason'),
            seasonId: BuiltValueNullFieldError.checkNotNull(
                seasonId, r'SeasonMembershipDto', 'seasonId'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'capabilities';
        capabilities.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'SeasonMembershipDto', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
