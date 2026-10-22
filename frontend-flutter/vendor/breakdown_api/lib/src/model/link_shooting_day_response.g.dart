// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'link_shooting_day_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$LinkShootingDayResponse extends LinkShootingDayResponse {
  @override
  final int linkedScenes;
  @override
  final int plannedSceneShoots;

  factory _$LinkShootingDayResponse(
          [void Function(LinkShootingDayResponseBuilder)? updates]) =>
      (LinkShootingDayResponseBuilder()..update(updates))._build();

  _$LinkShootingDayResponse._(
      {required this.linkedScenes, required this.plannedSceneShoots})
      : super._();
  @override
  LinkShootingDayResponse rebuild(
          void Function(LinkShootingDayResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  LinkShootingDayResponseBuilder toBuilder() =>
      LinkShootingDayResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is LinkShootingDayResponse &&
        linkedScenes == other.linkedScenes &&
        plannedSceneShoots == other.plannedSceneShoots;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, linkedScenes.hashCode);
    _$hash = $jc(_$hash, plannedSceneShoots.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'LinkShootingDayResponse')
          ..add('linkedScenes', linkedScenes)
          ..add('plannedSceneShoots', plannedSceneShoots))
        .toString();
  }
}

class LinkShootingDayResponseBuilder
    implements
        Builder<LinkShootingDayResponse, LinkShootingDayResponseBuilder> {
  _$LinkShootingDayResponse? _$v;

  int? _linkedScenes;
  int? get linkedScenes => _$this._linkedScenes;
  set linkedScenes(int? linkedScenes) => _$this._linkedScenes = linkedScenes;

  int? _plannedSceneShoots;
  int? get plannedSceneShoots => _$this._plannedSceneShoots;
  set plannedSceneShoots(int? plannedSceneShoots) =>
      _$this._plannedSceneShoots = plannedSceneShoots;

  LinkShootingDayResponseBuilder() {
    LinkShootingDayResponse._defaults(this);
  }

  LinkShootingDayResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _linkedScenes = $v.linkedScenes;
      _plannedSceneShoots = $v.plannedSceneShoots;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(LinkShootingDayResponse other) {
    _$v = other as _$LinkShootingDayResponse;
  }

  @override
  void update(void Function(LinkShootingDayResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  LinkShootingDayResponse build() => _build();

  _$LinkShootingDayResponse _build() {
    final _$result = _$v ??
        _$LinkShootingDayResponse._(
          linkedScenes: BuiltValueNullFieldError.checkNotNull(
              linkedScenes, r'LinkShootingDayResponse', 'linkedScenes'),
          plannedSceneShoots: BuiltValueNullFieldError.checkNotNull(
              plannedSceneShoots,
              r'LinkShootingDayResponse',
              'plannedSceneShoots'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
