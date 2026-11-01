// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

// Tier-1 pure tests for the AI-import cost display formatters (issue #675):
// integer nano-currency rendering (zero floats — design D2) with honest
// sub-cent precision (a non-free import never rounds to a displayed 0),
// and the mJ → Wh conversion.

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/ai_import/cost_format.dart';

void main() {
  group('costCurrencySymbol', () {
    test('USD renders \$, EUR renders €', () {
      expect(costCurrencySymbol(Currency.USD), r'$');
      expect(costCurrencySymbol(Currency.EUR), '€');
    });
  });

  group('formatNanoCurrency', () {
    test('whole major units render without a decimal point', () {
      expect(formatNanoCurrency(1000000000, Currency.USD), r'$1');
      expect(formatNanoCurrency(0, Currency.EUR), '€0');
      expect(formatNanoCurrency(1000000000, Currency.EUR), '€1');
    });

    test('sub-cent rates keep their visible decimals (never a shown \$0.00 '
        'for a non-zero rate)', () {
      // $1.45 / 1M tokens (design D2 example).
      expect(formatNanoCurrency(1450000000, Currency.USD), r'$1.45');
      // $0.2925 / 1M tokens (Neuralwatt flex example).
      expect(formatNanoCurrency(292500000, Currency.USD), r'$0.2925');
      // $0.003625 / 1M tokens (mimo cache read example).
      expect(formatNanoCurrency(3625000, Currency.USD), r'$0.003625');
    });

    test('trailing zeros are trimmed', () {
      expect(formatNanoCurrency(1500000000, Currency.USD), r'$1.5');
      expect(formatNanoCurrency(1200000000, Currency.USD), r'$1.2');
      expect(formatNanoCurrency(1000000, Currency.USD), r'$0.001');
    });

    test('negatives carry a minus sign', () {
      expect(formatNanoCurrency(-1450000000, Currency.USD), r'-$1.45');
    });

    test('typical per-import totals stay readable', () {
      // $0.0235 (spec scenario) and $0.00005 energy figure.
      expect(formatNanoCurrency(23500000, Currency.USD), r'$0.0235');
      expect(formatNanoCurrency(50000, Currency.USD), r'$0.00005');
    });

    test('sub-micro non-zero amounts never render as a displayed zero', () {
      // 500 nano = $0.0000005 — below the 6-decimal display floor, but a
      // non-zero cost must never fabricate a displayed zero (small energy
      // costs land here; CodeRabbit review, PR #699).
      expect(formatNanoCurrency(500, Currency.USD), r'$0.0000005');
      expect(formatNanoCurrency(-999, Currency.EUR), '-€0.000000999');
      // Larger figures keep the 6-decimal formatting (truncation stays
      // display-only for them; trailing zeros are still trimmed).
      expect(formatNanoCurrency(292500000, Currency.USD), r'$0.2925');
      expect(formatNanoCurrency(500000001, Currency.USD), r'$0.5');
    });
  });

  group('formatMillijoulesAsWh', () {
    test('exact conversions', () {
      expect(formatMillijoulesAsWh(3600000), '1');
      expect(formatMillijoulesAsWh(45000000), '12.5');
      expect(formatMillijoulesAsWh(0), '0');
    });

    test('sub-decimal values round half-up to hundredths', () {
      // 0.125 Wh → 0.13 (half-up, NOT banker's/truncation).
      expect(formatMillijoulesAsWh(450000), '0.13');
      // 0.011 Wh → 0.01.
      expect(formatMillijoulesAsWh(39600), '0.01');
      // 0.005 Wh — the exact half boundary rounds UP (half-up contract).
      expect(formatMillijoulesAsWh(18000), '0.01');
      // 0.00278 Wh rounds below the half boundary to a displayed '0' —
      // a display rounding, not a fabricated cost (the cost figures
      // themselves come from formatNanoCurrency with nano precision).
      expect(formatMillijoulesAsWh(10000), '0');
    });

    test('trailing zeros are trimmed', () {
      expect(formatMillijoulesAsWh(7200000), '2');
      expect(formatMillijoulesAsWh(36000000), '10');
    });

    test('negatives carry a minus sign', () {
      expect(formatMillijoulesAsWh(-3600000), '-1');
    });
  });

  group('costPrimaryFigure (issues #761/#768 — ONE rule for list + hero)', () {
    CostBreakdown cost({
      bool withToken = true,
      bool withEnergy = true,
      bool capped = false,
      CostStatus status = CostStatus.known,
      Currency? currency = Currency.USD,
      CostTotal? total,
    }) => CostBreakdown(
      (b) => b
        ..status = status
        ..currency = currency
        ..total = total?.toBuilder()
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
                  ..effectiveCappedNano = capped ? 23500000 : 50000
                  ..cappedByTokenCost = capped,
              ).toBuilder()
            : null,
    );

    CostTotal total(
      CostTotalStatus status, {
      int? totalNano,
      Currency? currency,
    }) => CostTotal(
      (b) => b
        ..status = status
        ..currency = currency
        ..totalNano = totalNano,
    );

    test('a known total wins under the token preference — the figure the user '
        'actually pays', () {
      final figure = costPrimaryFigure(
        cost(total: total(CostTotalStatus.known, totalNano: 23755000)),
        CostDisplayPreference.token,
      )!;
      expect(figure.kind, CostPrimaryKind.total);
      expect(figure.nano, 23755000);
      expect(figure.currency, Currency.USD);
    });

    test('a snapshot without a total falls back to the extraction token '
        'component (every pre-#768 row)', () {
      final figure = costPrimaryFigure(cost(), CostDisplayPreference.token)!;
      expect(figure.kind, CostPrimaryKind.tokenCost);
      expect(figure.nano, 23500000);
    });

    test('a refused total is never reconstructed from a component', () {
      for (final status in [
        CostTotalStatus.incomplete,
        CostTotalStatus.mixedCurrency,
        CostTotalStatus.unknown,
      ]) {
        final figure = costPrimaryFigure(
          cost(withEnergy: false, total: total(status)),
          CostDisplayPreference.token,
        )!;
        expect(figure.kind, CostPrimaryKind.tokenCost, reason: '$status');
        expect(figure.nano, 23500000, reason: '$status');
      }
    });

    test(
      'the energy preference selects the EFFECTIVE (capped) energy figure',
      () {
        final figure = costPrimaryFigure(
          cost(capped: true, total: total(CostTotalStatus.known, totalNano: 1)),
          CostDisplayPreference.energy,
        )!;
        expect(figure.kind, CostPrimaryKind.energyCost);
        expect(figure.nano, 23500000);
      },
    );

    test('the energy preference falls back to the money figure when no energy '
        'component exists', () {
      final figure = costPrimaryFigure(
        cost(
          withEnergy: false,
          total: total(CostTotalStatus.known, totalNano: 1),
        ),
        CostDisplayPreference.energy,
      )!;
      expect(figure.kind, CostPrimaryKind.total);
    });

    test('the total carries its own currency and is never converted (D2)', () {
      final figure = costPrimaryFigure(
        cost(
          total: total(
            CostTotalStatus.known,
            totalNano: 5,
            currency: Currency.EUR,
          ),
        ),
        CostDisplayPreference.token,
      )!;
      expect(figure.currency, Currency.EUR);
    });

    test('a priced component without a snapshot currency is not rendered', () {
      expect(
        costPrimaryFigure(cost(currency: null), CostDisplayPreference.token),
        isNull,
      );
    });

    test('unknown and not_applicable snapshots have no primary figure — the '
        'callers render the honest copy, never 0', () {
      expect(
        costPrimaryFigure(
          cost(status: CostStatus.unknown),
          CostDisplayPreference.token,
        ),
        isNull,
      );
      expect(
        costPrimaryFigure(
          cost(status: CostStatus.notApplicable),
          CostDisplayPreference.token,
        ),
        isNull,
      );
    });

    test('a defensive known snapshot with nothing priced has no primary '
        'figure', () {
      expect(
        costPrimaryFigure(
          cost(withToken: false, withEnergy: false),
          CostDisplayPreference.token,
        ),
        isNull,
      );
    });
  });
}
