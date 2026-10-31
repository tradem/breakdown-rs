// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Pure integer nano-currency cost calculations (issue #675).
//!
//! All money math uses **nano-units** — $10^{-9}$ of the currency unit
//! (`1_000_000_000` nano = 1.00 USD/EUR) — stored in `i64` with `i128`
//! intermediate products and half-up rounding to the nearest nano-unit.
//! There are **zero floats** in this module by design: standard cents
//! ($10^{-2}$) would round typical single-import costs ($0.0005–$0.008)
//! down to a lying `0`.
//!
//! Every function is pure and deterministic so workers, tests, and future
//! callers compute byte-identical snapshots.

use super::ports::{LlmCallUsage, LlmProvider};
use super::views::{
    CostBreakdown, CostStatus, CostTotal, CostTotalStatus, Currency, DecisionCostBreakdown,
    EnergyCostBreakdown, ImageCostBreakdown, ModelPricing, TokenCostBreakdown,
};

/// Nano-units per currency major unit (`1_000_000_000` nano = 1.00).
pub const NANO_PER_UNIT: i64 = 1_000_000_000;

/// Tokens one rate unit refers to (`…_nano_per_million` rates).
pub const TOKENS_PER_MILLION: i128 = 1_000_000;

/// Millijoules per kilowatt-hour (`1 kWh = 3.6 × 10^9 mJ`).
pub const MILLIJOULES_PER_KWH: i128 = 3_600_000_000;

/// Divide `num` by `den` (both `>= 0`, `den > 0`) with **half-up** rounding
/// to the nearest integer, clamped into `i64` (an overflow would mean a job
/// cost above ~$9.2 × 10^9, which the `BIGINT` column cannot hold either).
#[must_use]
pub fn div_half_up_nonneg(num: i128, den: i128) -> i64 {
    debug_assert!(den > 0, "denominator must be positive");
    debug_assert!(num >= 0, "numerator must be non-negative");
    let q = num / den;
    let r = num % den;
    let q = if r * 2 >= den { q + 1 } else { q };
    q.clamp(0, i64::MAX as i128) as i64
}

/// Cost of `tokens` at `rate_nano_per_million`, half-up rounded to nano.
///
/// Example: 10,000 tokens at $1.45/1M (`1_450_000_000`) = 14,500 nano
/// ($0.0000145). Zero tokens always cost exactly `0`.
#[must_use]
pub fn token_cost_nano(tokens: u64, rate_nano_per_million: i64) -> i64 {
    if tokens == 0 || rate_nano_per_million <= 0 {
        return 0;
    }
    div_half_up_nonneg(
        i128::from(tokens) * i128::from(rate_nano_per_million),
        TOKENS_PER_MILLION,
    )
}

/// Cost of cache-hit prompt tokens. `None` when the catalog carries no
/// dedicated cached rate (callers then bill cached tokens at the plain
/// input rate — never a fabricated discount).
#[must_use]
pub fn cached_input_cost_nano(cached_tokens: u64, cached_rate: Option<i64>) -> Option<i64> {
    cached_rate.map(|rate| token_cost_nano(cached_tokens, rate))
}

/// Uncapped energy cost of `energy_millijoules` at `rate_nano_per_kwh`,
/// half-up rounded to nano.
///
/// Example (spec scenario): 18,000 mJ at $10.00/kWh (`10_000_000_000`) =
/// 50,000 nano ($0.00005).
#[must_use]
pub fn energy_cost_raw_nano(energy_millijoules: u64, rate_nano_per_kwh: i64) -> i64 {
    if energy_millijoules == 0 || rate_nano_per_kwh <= 0 {
        return 0;
    }
    div_half_up_nonneg(
        i128::from(energy_millijoules) * i128::from(rate_nano_per_kwh),
        MILLIJOULES_PER_KWH,
    )
}

/// Neuralwatt surge-protection cap: the energy cost never exceeds the same
/// call's token cost. Returns `(effective_nano, capped_by_token_cost)`.
/// Exact equality is *not* a cap (nothing was reduced).
#[must_use]
pub fn cap_energy_by_token(raw_energy_nano: i64, token_total_nano: i64) -> (i64, bool) {
    if raw_energy_nano > token_total_nano {
        (token_total_nano, true)
    } else {
        (raw_energy_nano, false)
    }
}

/// Compute the token-cost breakdown for one job from its accumulated
/// telemetry and the pricing snapshot, or `None` when the snapshot is
/// `None` (the caller records [`CostStatus::Unknown`] instead).
///
/// Cached prompt tokens are billed at the catalog's cached rate when one
/// exists, otherwise at the plain input rate (no fabricated discount).
/// Uncached input tokens are `tokens_in − cached_tokens_in` (saturating).
#[must_use]
pub fn token_cost_breakdown(
    tokens_in: u64,
    tokens_out: u64,
    cached_tokens_in: u64,
    pricing: &ModelPricing,
) -> TokenCostBreakdown {
    let cached = cached_tokens_in.min(tokens_in);
    let uncached_in = tokens_in - cached;
    let cached_rate = pricing.cached_input_nano_per_million;

    let uncached_cost = token_cost_nano(uncached_in, pricing.input_nano_per_million);
    let cached_cost = cached_input_cost_nano(cached, cached_rate)
        .unwrap_or_else(|| token_cost_nano(cached, pricing.input_nano_per_million));
    let output_cost = token_cost_nano(tokens_out, pricing.output_nano_per_million);

    // i128 sum cannot overflow for realistic token counts (each component is
    // i64-clamped); saturate defensively into i64.
    let total_nano = (i128::from(uncached_cost) + i128::from(cached_cost) + i128::from(output_cost))
        .clamp(0, i64::MAX as i128) as i64;

    TokenCostBreakdown {
        tokens_in,
        tokens_out,
        cached_tokens_in: cached,
        input_rate_nano_per_million: pricing.input_nano_per_million,
        output_rate_nano_per_million: pricing.output_nano_per_million,
        cached_input_rate_nano_per_million: cached_rate,
        total_nano,
    }
}

/// One priced component's contribution to the total (issue #768).
///
/// `None` = the component was recorded but could not be priced; `Some(0)` is a
/// legitimate, fully priced zero.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct ComponentFigure {
    currency: Currency,
    total_nano: i64,
}

/// The sum of a component's token, energy and image figures. The energy figure
/// is the **effective** (possibly token-capped) one — the cost that counts.
fn component_figure(
    currency: Currency,
    token: Option<&TokenCostBreakdown>,
    energy: Option<&EnergyCostBreakdown>,
    image: Option<&ImageCostBreakdown>,
) -> ComponentFigure {
    let nano = i128::from(token.map_or(0, |t| t.total_nano))
        + i128::from(energy.map_or(0, |e| e.effective_capped_nano))
        + i128::from(image.map_or(0, |i| i.total_nano));
    ComponentFigure {
        currency,
        total_nano: nano.clamp(0, i64::MAX as i128) as i64,
    }
}

/// Fold the priced components into the figure the user pays (issue #768).
///
/// Honesty rules, in order:
/// - nothing recorded was priced → [`CostTotalStatus::Unknown`];
/// - a recorded component is unpriced → [`CostTotalStatus::Incomplete`] with no
///   number (a partial sum presented as "the total" would under-report);
/// - the components' rate cards disagree on the currency → design D2 forbids a
///   conversion, so [`CostTotalStatus::MixedCurrency`] with no number;
/// - otherwise [`CostTotalStatus::Known`] with the sum.
#[must_use]
fn fold_total(
    extraction: Option<(CostStatus, Option<ComponentFigure>)>,
    decision: Option<&DecisionCostBreakdown>,
) -> CostTotal {
    let extraction_figure = extraction.and_then(|(status, figure)| {
        if status == CostStatus::Known {
            figure
        } else {
            None
        }
    });
    let extraction_recorded = extraction.is_some();
    let decision_recorded = decision.is_some();
    if !extraction_recorded && !decision_recorded {
        return CostTotal::default();
    }

    let decision_figure = decision.and_then(|component| {
        match (
            component.status,
            component.currency,
            component.token_cost_nano,
            component.energy_cost_nano,
        ) {
            // `Known` without a token figure would be a broken snapshot; treating
            // it as unpriced keeps the total honest instead of summing a hole.
            (CostStatus::Known, Some(currency), Some(token), energy) => {
                let nano = i128::from(token) + i128::from(energy.unwrap_or(0));
                Some(ComponentFigure {
                    currency,
                    total_nano: nano.clamp(0, i64::MAX as i128) as i64,
                })
            }
            _ => None,
        }
    });

    match (
        extraction_recorded,
        extraction_figure,
        decision_recorded,
        decision_figure,
    ) {
        // A recorded component that could not be priced makes the total
        // incomplete — never a sum of the parts that happened to work.
        (true, None, _, _) | (_, _, true, None) => CostTotal {
            status: CostTotalStatus::Incomplete,
            currency: extraction_figure
                .map(|figure| figure.currency)
                .or_else(|| decision.and_then(|component| component.currency)),
            total_nano: None,
        },
        (_, Some(extraction), false, _) => CostTotal {
            status: CostTotalStatus::Known,
            currency: Some(extraction.currency),
            total_nano: Some(extraction.total_nano),
        },
        (false, _, _, Some(decision)) => CostTotal {
            status: CostTotalStatus::Known,
            currency: Some(decision.currency),
            total_nano: Some(decision.total_nano),
        },
        (_, Some(extraction), true, Some(decision)) => {
            if extraction.currency != decision.currency {
                return CostTotal {
                    status: CostTotalStatus::MixedCurrency,
                    currency: None,
                    total_nano: None,
                };
            }
            let nano = i128::from(extraction.total_nano) + i128::from(decision.total_nano);
            CostTotal {
                status: CostTotalStatus::Known,
                currency: Some(extraction.currency),
                total_nano: Some(nano.clamp(0, i64::MAX as i128) as i64),
            }
        }
        // Unreachable by construction (the two catch-alls above cover every
        // remaining arm), but written as the honest alternative rather than an
        // `unreachable!()` (AGENTS.md §3).
        (_, None, false, None) => CostTotal::default(),
    }
}

/// Compute the **Decision-Model** component of a job's cost snapshot (issue
/// #768): its own usage, its own rate card, its own currency.
///
/// `pricing` is the `ai_model_pricing` row of the **Decision Model** — never
/// the extraction model's. A missing row (or a provider that does not bill) is
/// the honest unknown: `status = Unknown` with every priced field `None`, the
/// usage counts kept, and **no** fallback to the extraction rate.
#[must_use]
pub fn decision_cost_breakdown(
    provider: LlmProvider,
    model: &str,
    usage: LlmCallUsage,
    pricing: Option<&ModelPricing>,
) -> DecisionCostBreakdown {
    let unpriced = |status: CostStatus| DecisionCostBreakdown {
        provider,
        model: model.to_owned(),
        status,
        tokens_in: usage.tokens_in,
        tokens_out: usage.tokens_out,
        cached_tokens_in: usage.cached_tokens_in,
        energy_millijoules: usage.energy_millijoules,
        currency: None,
        price_as_of: None,
        pricing_source: None,
        input_rate_nano_per_million: None,
        output_rate_nano_per_million: None,
        cached_input_rate_nano_per_million: None,
        energy_rate_nano_per_kwh: None,
        token_cost_nano: None,
        energy_cost_nano: None,
    };

    let Some(pricing) = pricing else {
        return unpriced(CostStatus::Unknown);
    };

    let token = token_cost_breakdown(
        usage.tokens_in,
        usage.tokens_out,
        usage.cached_tokens_in,
        pricing,
    );
    // The energy cap pairs a provider's energy rate with *its own* token cost —
    // the reason the two components must never share an accumulator.
    let (energy_rate, energy_cost_nano) = match pricing.energy_nano_per_kwh {
        Some(rate) if usage.energy_millijoules > 0 => {
            let raw = energy_cost_raw_nano(usage.energy_millijoules, rate);
            let (effective, _capped) = if pricing.energy_capped_by_token {
                cap_energy_by_token(raw, token.total_nano)
            } else {
                (raw, false)
            };
            (Some(rate), Some(effective))
        }
        rate => (rate, None),
    };

    DecisionCostBreakdown {
        provider,
        model: model.to_owned(),
        status: CostStatus::Known,
        tokens_in: usage.tokens_in,
        tokens_out: usage.tokens_out,
        cached_tokens_in: usage.cached_tokens_in,
        energy_millijoules: usage.energy_millijoules,
        currency: Some(pricing.currency),
        price_as_of: Some(pricing.price_as_of),
        pricing_source: Some(pricing.pricing_source),
        input_rate_nano_per_million: Some(pricing.input_nano_per_million),
        output_rate_nano_per_million: Some(pricing.output_nano_per_million),
        cached_input_rate_nano_per_million: pricing.cached_input_nano_per_million,
        energy_rate_nano_per_kwh: energy_rate,
        token_cost_nano: Some(token.total_nano),
        energy_cost_nano,
    }
}

/// Snapshot for a job whose **extraction** `(provider, model)` could not be
/// priced, with the Decision-Model component attached when it could be priced on
/// its own (issue #768).
///
/// The snapshot `status` stays [`CostStatus::Unknown`] — it describes the
/// extraction component — while the decision component carries its own status
/// and the total degrades to `incomplete` rather than silently dropping the
/// priced part.
#[must_use]
pub fn cost_breakdown_unpriced(decision: Option<DecisionCostBreakdown>) -> CostBreakdown {
    CostBreakdown {
        decision: decision.clone(),
        total: fold_total(None, decision.as_ref()),
        ..CostBreakdown::unknown()
    }
}

/// Compute the full [`CostBreakdown`] snapshot for a completed job (design
/// D3/D4). `pricing` is the **extraction** model's `ai_model_pricing` row active
/// at completion; `None` yields [`CostStatus::Unknown`] (never zero-filled).
/// `decision` is the already-priced Decision-Model component (issue #768) —
/// `Some` only when the job issued a Decision-Model call — and contributes to
/// [`CostBreakdown::total`] with **its own** already-computed figure.
#[must_use]
pub fn cost_breakdown(
    tokens_in: u64,
    tokens_out: u64,
    cached_tokens_in: u64,
    energy_millijoules: u64,
    pricing: Option<&ModelPricing>,
    decision: Option<DecisionCostBreakdown>,
) -> CostBreakdown {
    let Some(pricing) = pricing else {
        return cost_breakdown_unpriced(decision);
    };

    let token_cost = token_cost_breakdown(tokens_in, tokens_out, cached_tokens_in, pricing);

    let energy_cost = match pricing.energy_nano_per_kwh {
        Some(rate) if energy_millijoules > 0 => {
            let raw = energy_cost_raw_nano(energy_millijoules, rate);
            let (effective, capped) = if pricing.energy_capped_by_token {
                cap_energy_by_token(raw, token_cost.total_nano)
            } else {
                (raw, false)
            };
            Some(EnergyCostBreakdown {
                energy_millijoules,
                rate_nano_per_kwh: rate,
                raw_energy_nano: raw,
                effective_capped_nano: effective,
                capped_by_token_cost: capped,
            })
        }
        _ => None,
    };

    let total = fold_total(
        Some((
            CostStatus::Known,
            Some(component_figure(
                pricing.currency,
                Some(&token_cost),
                energy_cost.as_ref(),
                None,
            )),
        )),
        decision.as_ref(),
    );

    CostBreakdown {
        status: CostStatus::Known,
        currency: Some(pricing.currency),
        price_as_of: Some(pricing.price_as_of),
        pricing_source: Some(pricing.pricing_source),
        token_cost: Some(token_cost),
        energy_cost,
        image_cost: None,
        decision,
        total,
    }
}

#[cfg(test)]
#[path = "cost_tests.rs"]
mod cost_tests;
