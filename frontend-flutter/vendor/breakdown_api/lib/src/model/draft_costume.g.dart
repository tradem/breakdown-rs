// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'draft_costume.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$DraftCostume extends DraftCostume {
  @override
  final String characterName;
  @override
  final String description;
  @override
  final String sourceQuote;

  factory _$DraftCostume([void Function(DraftCostumeBuilder)? updates]) =>
      (DraftCostumeBuilder()..update(updates))._build();

  _$DraftCostume._(
      {required this.characterName,
      required this.description,
      required this.sourceQuote})
      : super._();
  @override
  DraftCostume rebuild(void Function(DraftCostumeBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  DraftCostumeBuilder toBuilder() => DraftCostumeBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is DraftCostume &&
        characterName == other.characterName &&
        description == other.description &&
        sourceQuote == other.sourceQuote;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, characterName.hashCode);
    _$hash = $jc(_$hash, description.hashCode);
    _$hash = $jc(_$hash, sourceQuote.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'DraftCostume')
          ..add('characterName', characterName)
          ..add('description', description)
          ..add('sourceQuote', sourceQuote))
        .toString();
  }
}

class DraftCostumeBuilder
    implements Builder<DraftCostume, DraftCostumeBuilder> {
  _$DraftCostume? _$v;

  String? _characterName;
  String? get characterName => _$this._characterName;
  set characterName(String? characterName) =>
      _$this._characterName = characterName;

  String? _description;
  String? get description => _$this._description;
  set description(String? description) => _$this._description = description;

  String? _sourceQuote;
  String? get sourceQuote => _$this._sourceQuote;
  set sourceQuote(String? sourceQuote) => _$this._sourceQuote = sourceQuote;

  DraftCostumeBuilder() {
    DraftCostume._defaults(this);
  }

  DraftCostumeBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _characterName = $v.characterName;
      _description = $v.description;
      _sourceQuote = $v.sourceQuote;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(DraftCostume other) {
    _$v = other as _$DraftCostume;
  }

  @override
  void update(void Function(DraftCostumeBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  DraftCostume build() => _build();

  _$DraftCostume _build() {
    final _$result = _$v ??
        _$DraftCostume._(
          characterName: BuiltValueNullFieldError.checkNotNull(
              characterName, r'DraftCostume', 'characterName'),
          description: BuiltValueNullFieldError.checkNotNull(
              description, r'DraftCostume', 'description'),
          sourceQuote: BuiltValueNullFieldError.checkNotNull(
              sourceQuote, r'DraftCostume', 'sourceQuote'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
