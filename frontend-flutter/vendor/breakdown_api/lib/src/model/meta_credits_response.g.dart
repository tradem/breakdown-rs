// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'meta_credits_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$MetaCreditsResponse extends MetaCreditsResponse {
  @override
  final BuiltList<MetaCreditsEntry> credits;

  factory _$MetaCreditsResponse(
          [void Function(MetaCreditsResponseBuilder)? updates]) =>
      (MetaCreditsResponseBuilder()..update(updates))._build();

  _$MetaCreditsResponse._({required this.credits}) : super._();
  @override
  MetaCreditsResponse rebuild(
          void Function(MetaCreditsResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  MetaCreditsResponseBuilder toBuilder() =>
      MetaCreditsResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is MetaCreditsResponse && credits == other.credits;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, credits.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'MetaCreditsResponse')
          ..add('credits', credits))
        .toString();
  }
}

class MetaCreditsResponseBuilder
    implements Builder<MetaCreditsResponse, MetaCreditsResponseBuilder> {
  _$MetaCreditsResponse? _$v;

  ListBuilder<MetaCreditsEntry>? _credits;
  ListBuilder<MetaCreditsEntry> get credits =>
      _$this._credits ??= ListBuilder<MetaCreditsEntry>();
  set credits(ListBuilder<MetaCreditsEntry>? credits) =>
      _$this._credits = credits;

  MetaCreditsResponseBuilder() {
    MetaCreditsResponse._defaults(this);
  }

  MetaCreditsResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _credits = $v.credits.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(MetaCreditsResponse other) {
    _$v = other as _$MetaCreditsResponse;
  }

  @override
  void update(void Function(MetaCreditsResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  MetaCreditsResponse build() => _build();

  _$MetaCreditsResponse _build() {
    _$MetaCreditsResponse _$result;
    try {
      _$result = _$v ??
          _$MetaCreditsResponse._(
            credits: credits.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'credits';
        credits.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'MetaCreditsResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
