// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meta_credits_entry.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetaCreditsEntry extends MetaCreditsEntry {
  @override
  final String name;
  @override
  final String? provider;
  @override
  final BuiltList<String> roles;

  factory _$MetaCreditsEntry(
          [void Function(MetaCreditsEntryBuilder)? updates]) =>
      (MetaCreditsEntryBuilder()..update(updates))._build();

  _$MetaCreditsEntry._({required this.name, this.provider, required this.roles})
      : super._();
  @override
  MetaCreditsEntry rebuild(void Function(MetaCreditsEntryBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MetaCreditsEntryBuilder toBuilder() =>
      MetaCreditsEntryBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetaCreditsEntry &&
        name == other.name &&
        provider == other.provider &&
        roles == other.roles;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, provider.hashCode);
    _$hash = $jc(_$hash, roles.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetaCreditsEntry')
          ..add('name', name)
          ..add('provider', provider)
          ..add('roles', roles))
        .toString();
  }
}

class MetaCreditsEntryBuilder
    implements Builder<MetaCreditsEntry, MetaCreditsEntryBuilder> {
  _$MetaCreditsEntry? _$v;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _provider;
  String? get provider => _$this._provider;
  set provider(String? provider) => _$this._provider = provider;

  ListBuilder<String>? _roles;
  ListBuilder<String> get roles => _$this._roles ??= ListBuilder<String>();
  set roles(ListBuilder<String>? roles) => _$this._roles = roles;

  MetaCreditsEntryBuilder() {
    MetaCreditsEntry._defaults(this);
  }

  MetaCreditsEntryBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _name = $v.name;
      _provider = $v.provider;
      _roles = $v.roles.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetaCreditsEntry other) {
    _$v = other as _$MetaCreditsEntry;
  }

  @override
  void update(void Function(MetaCreditsEntryBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetaCreditsEntry build() => _build();

  _$MetaCreditsEntry _build() {
    _$MetaCreditsEntry _$result;
    try {
      _$result = _$v ??
          _$MetaCreditsEntry._(
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'MetaCreditsEntry', 'name'),
            provider: provider,
            roles: roles.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'roles';
        roles.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MetaCreditsEntry', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
