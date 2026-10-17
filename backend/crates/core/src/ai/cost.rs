// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

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

use super::views::{
    CostBreakdown, CostStatus, EnergyCostBreakdown, ModelPricing, TokenCostBreakdown,
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

/// Compute the full [`CostBreakdown`] snapshot for a completed job (design
/// D3/D4). `pricing` is the `ai_model_pricing` row active at completion;
/// `None` yields [`CostStatus::Unknown`] (never zero-filled).
#[must_use]
pub fn cost_breakdown(
    tokens_in: u64,
    tokens_out: u64,
    cached_tokens_in: u64,
    energy_millijoules: u64,
    pricing: Option<&ModelPricing>,
) -> CostBreakdown {
    let Some(pricing) = pricing else {
        return CostBreakdown::unknown();
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

    CostBreakdown {
        status: CostStatus::Known,
        currency: Some(pricing.currency),
        price_as_of: Some(pricing.price_as_of),
        pricing_source: Some(pricing.pricing_source),
        token_cost: Some(token_cost),
        energy_cost,
        image_cost: None,
    }
}

#[cfg(test)]
#[path = "cost_tests.rs"]
mod cost_tests;
