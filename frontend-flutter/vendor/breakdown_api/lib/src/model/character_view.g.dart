// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'character_view.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$CharacterView extends CharacterView {
  @override
  final CharacterCategory category;
  @override
  final ContactInfo contact;
  @override
  final String id;
  @override
  final CharacterMeasurements measurements;
  @override
  final String name;
  @override
  final String seasonId;
  @override
  final DateTime updatedAt;
  @override
  final int version;

  factory _$CharacterView([void Function(CharacterViewBuilder)? updates]) =>
      (CharacterViewBuilder()..update(updates))._build();

  _$CharacterView._(
      {required this.category,
      required this.contact,
      required this.id,
      required this.measurements,
      required this.name,
      required this.seasonId,
      required this.updatedAt,
      required this.version})
      : super._();
  @override
  CharacterView rebuild(void Function(CharacterViewBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  CharacterViewBuilder toBuilder() => CharacterViewBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is CharacterView &&
        category == other.category &&
        contact == other.contact &&
        id == other.id &&
        measurements == other.measurements &&
        name == other.name &&
        seasonId == other.seasonId &&
        updatedAt == other.updatedAt &&
        version == other.version;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, category.hashCode);
    _$hash = $jc(_$hash, contact.hashCode);
    _$hash = $jc(_$hash, id.hashCode);
    _$hash = $jc(_$hash, measurements.hashCode);
    _$hash = $jc(_$hash, name.hashCode);
    _$hash = $jc(_$hash, seasonId.hashCode);
    _$hash = $jc(_$hash, updatedAt.hashCode);
    _$hash = $jc(_$hash, version.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'CharacterView')
          ..add('category', category)
          ..add('contact', contact)
          ..add('id', id)
          ..add('measurements', measurements)
          ..add('name', name)
          ..add('seasonId', seasonId)
          ..add('updatedAt', updatedAt)
          ..add('version', version))
        .toString();
  }
}

class CharacterViewBuilder
    implements Builder<CharacterView, CharacterViewBuilder> {
  _$CharacterView? _$v;

  CharacterCategory? _category;
  CharacterCategory? get category => _$this._category;
  set category(CharacterCategory? category) => _$this._category = category;

  ContactInfoBuilder? _contact;
  ContactInfoBuilder get contact => _$this._contact ??= ContactInfoBuilder();
  set contact(ContactInfoBuilder? contact) => _$this._contact = contact;

  String? _id;
  String? get id => _$this._id;
  set id(String? id) => _$this._id = id;

  CharacterMeasurementsBuilder? _measurements;
  CharacterMeasurementsBuilder get measurements =>
      _$this._measurements ??= CharacterMeasurementsBuilder();
  set measurements(CharacterMeasurementsBuilder? measurements) =>
      _$this._measurements = measurements;

  String? _name;
  String? get name => _$this._name;
  set name(String? name) => _$this._name = name;

  String? _seasonId;
  String? get seasonId => _$this._seasonId;
  set seasonId(String? seasonId) => _$this._seasonId = seasonId;

  DateTime? _updatedAt;
  DateTime? get updatedAt => _$this._updatedAt;
  set updatedAt(DateTime? updatedAt) => _$this._updatedAt = updatedAt;

  int? _version;
  int? get version => _$this._version;
  set version(int? version) => _$this._version = version;

  CharacterViewBuilder() {
    CharacterView._defaults(this);
  }

  CharacterViewBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _category = $v.category;
      _contact = $v.contact.toBuilder();
      _id = $v.id;
      _measurements = $v.measurements.toBuilder();
      _name = $v.name;
      _seasonId = $v.seasonId;
      _updatedAt = $v.updatedAt;
      _version = $v.version;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(CharacterView other) {
    _$v = other as _$CharacterView;
  }

  @override
  void update(void Function(CharacterViewBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  CharacterView build() => _build();

  _$CharacterView _build() {
    _$CharacterView _$result;
    try {
      _$result = _$v ??
          _$CharacterView._(
            category: BuiltValueNullFieldError.checkNotNull(
                category, r'CharacterView', 'category'),
            contact: contact.build(),
            id: BuiltValueNullFieldError.checkNotNull(
                id, r'CharacterView', 'id'),
            measurements: measurements.build(),
            name: BuiltValueNullFieldError.checkNotNull(
                name, r'CharacterView', 'name'),
            seasonId: BuiltValueNullFieldError.checkNotNull(
                seasonId, r'CharacterView', 'seasonId'),
            updatedAt: BuiltValueNullFieldError.checkNotNull(
                updatedAt, r'CharacterView', 'updatedAt'),
            version: BuiltValueNullFieldError.checkNotNull(
                version, r'CharacterView', 'version'),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'contact';
        contact.build();

        _$failedField = 'measurements';
        measurements.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'CharacterView', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
