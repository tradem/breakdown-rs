// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-1 unit tests for the pure half of the job-status cost card (issues
// #761/#768): which figure becomes the hero, what it is labelled, and when the
// card must state that no honest total exists. No widgets, no Flutter binding.
//
// The honesty matrix of #675 is re-asserted here on the pure decision: an
// `unknown` snapshot renders the localized "Unknown" and NEVER a fabricated
// `0`, an unpriced component is never replaced by the extraction rate, and a
// refused total (`incomplete` / `mixed_currency`) is not presented as a
// component dressed up as the sum.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/material_icons.dart';
import 'package:frontend_flutter/features/ai_import/import_jobs/job_cost_card.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_de.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations_en.dart';

/// A `known` snapshot priced in USD with a token component ($0.0235) and,
/// optionally, an energy component ($0.00005, or the capped $0.0235).
CostBreakdown _cost({
  bool withToken = true,
  bool withEnergy = true,
  bool capped = false,
  bool known = true,
  Currency? currency = Currency.USD,
}) => CostBreakdown(
  (b) => b
    ..status = known ? CostStatus.known : CostStatus.unknown
    ..currency = currency
    ..priceAsOf = DateTime.utc(2026, 1, 1)
    ..pricingSource = PricingSource.curatedSeed
    ..tokenCost = withToken
        ? TokenCostBreakdown(
            (t) => t
              ..tokensIn = 4700
              ..tokensOut = 1200
              ..cachedTokensIn = 500
              ..inputRateNanoPerMillion = 1450000000
              ..outputRateNanoPerMillion = 4000000000
              ..totalNano = 23500000,
          ).toBuilder()
        : null
    ..energyCost = withEnergy
        ? EnergyCostBreakdown(
            (t) => t
              ..energyMillijoules = 1800000
              ..rateNanoPerKwh = 10000000000
              ..rawEnergyNano = 50000
              // A capped request: the EFFECTIVE figure is the one that counts.
              ..effectiveCappedNano = capped ? 23500000 : 50000
              ..cappedByTokenCost = capped,
          ).toBuilder()
        : null,
);

CostTotal _total(CostTotalStatus status, {int? totalNano}) => CostTotal(
  (b) => b
    ..status = status
    ..currency = Currency.USD
    ..totalNano = totalNano,
);

CostBreakdown _withTotal(CostBreakdown cost, CostTotal? total) =>
    cost.rebuild((b) => b..total = total?.toBuilder());

CostBreakdown _unknownCost() =>
    CostBreakdown((b) => b..status = CostStatus.unknown);

CostBreakdown _notApplicableCost() =>
    CostBreakdown((b) => b..status = CostStatus.notApplicable);

void main() {
  final en = AppLocalizationsEn();
  final de = AppLocalizationsDe();

  group('aiCostHero (issue #761/#768)', () {
    test('a published total is the hero under the default (token) '
        'preference — labelled, never an unlabelled number', () {
      final hero = aiCostHero(
        en,
        _withTotal(_cost(), _total(CostTotalStatus.known, totalNano: 23550000)),
        CostDisplayPreference.token,
      );
      expect(hero.label, 'Total cost');
      expect(hero.value, r'$0.02355');
      expect(hero.isUnknown, isFalse);
      expect(hero.note, isNull);
    });

    test('the energy preference swaps the hero to the energy component, using '
        'the EFFECTIVE (capped) figure', () {
      final hero = aiCostHero(
        en,
        _withTotal(
          _cost(capped: true),
          _total(CostTotalStatus.known, totalNano: 47000000),
        ),
        CostDisplayPreference.energy,
      );
      expect(hero.label, 'Energy cost');
      // effective_capped_nano, not raw_energy_nano.
      expect(hero.value, r'$0.0235');
    });

    test('the energy preference degrades to the money figure when the '
        'snapshot recorded no energy telemetry (never an invented figure)', () {
      final hero = aiCostHero(
        en,
        _withTotal(
          _cost(withEnergy: false),
          _total(CostTotalStatus.known, totalNano: 23500000),
        ),
        CostDisplayPreference.energy,
      );
      expect(hero.label, 'Total cost');
      expect(hero.value, r'$0.0235');
    });

    test('a pre-#768 snapshot (no total) shows the token component and claims '
        'no total — an absence is not an error', () {
      final hero = aiCostHero(en, _cost(), CostDisplayPreference.token);
      expect(hero.label, 'Token cost');
      expect(hero.value, r'$0.0235');
      expect(hero.note, isNull);
    });

    test('an `incomplete` total is refused WITH a reason instead of being '
        'presented as the sum', () {
      final hero = aiCostHero(
        en,
        _withTotal(_cost(), _total(CostTotalStatus.incomplete)),
        CostDisplayPreference.token,
      );
      expect(hero.label, 'Token cost');
      expect(
        hero.note,
        'Total unavailable — one cost component is not priced.',
      );
    });

    test(
      'a `mixed_currency` total is refused: design D2 forbids a conversion',
      () {
        final hero = aiCostHero(
          en,
          _withTotal(_cost(), _total(CostTotalStatus.mixedCurrency)),
          CostDisplayPreference.token,
        );
        expect(
          hero.note,
          'Total unavailable — the components are priced in different '
          'currencies.',
        );
      },
    );

    test('an `unknown` total (every not-applicable / unknown snapshot) is an '
        'absence, so it renders no reason', () {
      final hero = aiCostHero(
        en,
        _withTotal(_cost(), _total(CostTotalStatus.unknown)),
        CostDisplayPreference.token,
      );
      expect(hero.note, isNull);
      expect(hero.label, 'Token cost');
    });

    test('an unknown cost renders the localized Unknown — NEVER 0', () {
      final hero = aiCostHero(en, _unknownCost(), CostDisplayPreference.token);
      expect(hero.value, 'Unknown');
      expect(hero.isUnknown, isTrue);
      expect(hero.value.contains('0'), isFalse);
    });

    test('an unknown cost under the energy preference still names the metric '
        'the user asked for', () {
      final hero = aiCostHero(en, _unknownCost(), CostDisplayPreference.energy);
      expect(hero.label, 'Energy cost');
      expect(hero.value, 'Unknown');
    });

    test('a `known` snapshot without a currency degrades to the honest '
        'unknown instead of formatting a symbol-less number', () {
      final hero = aiCostHero(
        en,
        _cost(currency: null),
        CostDisplayPreference.token,
      );
      expect(hero.isUnknown, isTrue);
      expect(hero.value, 'Unknown');
    });

    test('an energy-only snapshot under the token preference shows the energy '
        'figure rather than inventing a token cost', () {
      final hero = aiCostHero(
        en,
        _cost(withToken: false),
        CostDisplayPreference.token,
      );
      expect(hero.label, 'Energy cost');
      expect(hero.value, r'$0.00005');
    });

    test('a defensive `known` snapshot with no priced component at all stays '
        'honest', () {
      final hero = aiCostHero(
        en,
        _cost(withToken: false, withEnergy: false),
        CostDisplayPreference.token,
      );
      expect(hero.isUnknown, isTrue);
      expect(hero.value, 'Unknown');
    });

    test('the labels come from the catalogs (de + en), so no copy is authored '
        'in the widget', () {
      final german = aiCostHero(
        de,
        _withTotal(_cost(), _total(CostTotalStatus.known, totalNano: 23550000)),
        CostDisplayPreference.token,
      );
      expect(german.label, 'Gesamtkosten');
      expect(
        aiCostHero(de, _cost(), CostDisplayPreference.energy).label,
        'Energiekosten',
      );
    });
  });

  group('aiJobCostMetricIcon (issue #761)', () {
    test('no snapshot yields no metric glyph', () {
      expect(
        aiJobCostMetricIcon(null, CostDisplayPreference.token),
        BreakdownMaterialIcons.aiJobCostUnknown,
      );
    });

    test('a known token-priced snapshot yields the money glyph', () {
      expect(
        aiJobCostMetricIcon(_cost(), CostDisplayPreference.token),
        BreakdownMaterialIcons.aiJobCostToken,
      );
    });

    test('the energy preference yields the energy glyph when the snapshot '
        'carries energy', () {
      expect(
        aiJobCostMetricIcon(_cost(), CostDisplayPreference.energy),
        BreakdownMaterialIcons.aiJobCostEnergy,
      );
    });

    test('the energy preference falls back to the money glyph when the '
        'snapshot carries no energy (the figure it shows)', () {
      expect(
        aiJobCostMetricIcon(
          _cost(withEnergy: false),
          CostDisplayPreference.energy,
        ),
        BreakdownMaterialIcons.aiJobCostToken,
      );
    });

    test('an unknown cost yields the help glyph — never a currency glyph', () {
      expect(
        aiJobCostMetricIcon(_unknownCost(), CostDisplayPreference.token),
        BreakdownMaterialIcons.aiJobCostUnknown,
      );
    });

    test('a not-applicable cost yields the no-billing glyph', () {
      expect(
        aiJobCostMetricIcon(_notApplicableCost(), CostDisplayPreference.token),
        BreakdownMaterialIcons.aiJobCostNotApplicable,
      );
    });
  });
}
