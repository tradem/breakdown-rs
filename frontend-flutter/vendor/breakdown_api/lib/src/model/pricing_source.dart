// GENERATED — do not edit. Regenerate with `scripts/regen-client.sh`.

//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'pricing_source.g.dart';

/// Where a pricing row came from. `CuratedSeed` rows are written by the SQL migration so freshly booted, offline deployments have deterministic pricing; the refresh worker overwrites them with `ProviderLive` (provider `/models` endpoints) or `ModelsDev` (`models.dev/api.json`) rows.
class PricingSource extends EnumClass {
  @BuiltValueEnumConst(wireName: r'curated_seed')
  static const PricingSource curatedSeed = _$curatedSeed;
  @BuiltValueEnumConst(wireName: r'provider_live')
  static const PricingSource providerLive = _$providerLive;
  @BuiltValueEnumConst(wireName: r'models_dev')
  static const PricingSource modelsDev = _$modelsDev;

  static Serializer<PricingSource> get serializer => _$pricingSourceSerializer;

  const PricingSource._(String name) : super(name);

  static BuiltSet<PricingSource> get values => _$values;
  static PricingSource valueOf(String name) => _$valueOf(name);
}

/// Optionally, enum_class can generate a mixin to go with your enum for use
/// with Angular. It exposes your enum constants as getters. So, if you mix it
/// in to your Dart component class, the values become available to the
/// corresponding Angular template.
///
/// Trigger mixin generation by writing a line like this one next to your enum.
abstract class PricingSourceMixin = Object with _$PricingSourceMixin;
