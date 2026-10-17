// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

use super::{
    cached_input_cost_nano, cap_energy_by_token, cost_breakdown, div_half_up_nonneg,
    energy_cost_raw_nano, token_cost_breakdown, token_cost_nano,
};
use crate::ai::views::{CostStatus, Currency, ModelPricing, PricingSource};

fn usd_pricing() -> ModelPricing {
    ModelPricing {
        currency: Currency::Usd,
        input_nano_per_million: 1_450_000_000,  // $1.45 / 1M in
        output_nano_per_million: 4_500_000_000, // $4.50 / 1M out
        cached_input_nano_per_million: Some(362_500_000),
        energy_nano_per_kwh: Some(10_000_000_000), // $10.00 / kWh
        energy_capped_by_token: true,
        image_output_nano_per_million: None,
        image_nano_per_unit: None,
        pricing_source: PricingSource::CuratedSeed,
        price_as_of: chrono::DateTime::from_timestamp(1_768_478_400, 0)
            .expect("static valid timestamp"),
    }
}

// --- div_half_up_nonneg -----------------------------------------------------

#[test]
fn div_half_up_rounds_half_up() {
    assert_eq!(div_half_up_nonneg(1_500, 1_000), 2);
    assert_eq!(div_half_up_nonneg(1_499, 1_000), 1);
    assert_eq!(div_half_up_nonneg(500, 1_000), 1);
    assert_eq!(div_half_up_nonneg(499, 1_000), 0);
}

#[test]
fn div_half_up_exact_division_is_exact() {
    assert_eq!(div_half_up_nonneg(2_000, 1_000), 2);
    assert_eq!(div_half_up_nonneg(0, 1_000), 0);
}

// --- token_cost_nano ---------------------------------------------------------

#[test]
fn token_cost_matches_spec_examples() {
    // 10,000 in at $1.45/1M -> $0.0145 = 14_500_000 nano
    assert_eq!(token_cost_nano(10_000, 1_450_000_000), 14_500_000);
    // 2,000 out at $4.50/1M -> $0.009 = 9_000_000 nano
    assert_eq!(token_cost_nano(2_000, 4_500_000_000), 9_000_000);
    // Spec scenario total: 10_000 in + 2_000 out = 23_500_000 nano = $0.0235
    assert_eq!(
        token_cost_nano(10_000, 1_450_000_000) + token_cost_nano(2_000, 4_500_000_000),
        23_500_000
    );
}

#[test]
fn token_cost_zero_tokens_is_zero() {
    assert_eq!(token_cost_nano(0, 1_450_000_000), 0);
}

#[test]
fn token_cost_sub_nano_rounds_half_up_not_to_zero_lying() {
    // 1 token at $1.45/1M = 1450 nano exactly.
    assert_eq!(token_cost_nano(1, 1_450_000_000), 1_450);
    // $0.2925/1M (Neuralwatt flex): 1 token = 292.5 nano -> rounds to 293.
    assert_eq!(token_cost_nano(1, 292_500_000), 293);
    // Cache-read rate $0.003625/1M: 1 token = 3.625 nano -> rounds to 4.
    assert_eq!(token_cost_nano(1, 3_625_000), 4);
}

// --- cached_input_cost_nano --------------------------------------------------

#[test]
fn cached_cost_requires_a_rate() {
    assert_eq!(cached_input_cost_nano(1_000, None), None);
    assert_eq!(
        cached_input_cost_nano(1_000, Some(362_500_000)),
        Some(362_500) // 1_000 × 362_500_000 / 1e6 = 362_500 nano
    );
}

// --- energy_cost_raw_nano ----------------------------------------------------

#[test]
fn energy_cost_matches_spec_scenario() {
    // 18,000 mJ at $10.00/kWh -> $0.00005 = 50_000 nano.
    assert_eq!(energy_cost_raw_nano(18_000, 10_000_000_000), 50_000);
}

#[test]
fn energy_cost_zero_millijoules_is_zero() {
    assert_eq!(energy_cost_raw_nano(0, 10_000_000_000), 0);
}

#[test]
fn energy_cost_one_kwh_exactly_is_the_rate() {
    assert_eq!(
        energy_cost_raw_nano(3_600_000_000, 10_000_000_000),
        10_000_000_000
    );
}

#[test]
fn energy_cost_rounds_half_up() {
    // 1 mJ at $10/kWh = 10_000_000_000 / 3.6e9 = 2.777… nano -> 3.
    assert_eq!(energy_cost_raw_nano(1, 10_000_000_000), 3);
}

// --- cap_energy_by_token -----------------------------------------------------

#[test]
fn cap_only_engages_when_raw_exceeds_token_total() {
    assert_eq!(cap_energy_by_token(50_000, 23_500_000), (50_000, false));
    assert_eq!(
        cap_energy_by_token(23_500_001, 23_500_000),
        (23_500_000, true)
    );
    // Exact equality is not a cap.
    assert_eq!(
        cap_energy_by_token(23_500_000, 23_500_000),
        (23_500_000, false)
    );
}

// --- token_cost_breakdown ----------------------------------------------------

#[test]
fn breakdown_splits_uncached_and_cached_input() {
    let p = usd_pricing();
    let b = token_cost_breakdown(10_000, 2_000, 4_000, &p);
    assert_eq!(b.tokens_in, 10_000);
    assert_eq!(b.cached_tokens_in, 4_000);
    // 6_000 uncached at $1.45/1M = 8_700_000 nano; 4_000 cached at
    // $0.3625/1M = 1_450_000 nano; 2_000 out at $4.50/1M = 9_000_000 nano.
    assert_eq!(b.total_nano, 8_700_000 + 1_450_000 + 9_000_000);
    assert_eq!(b.cached_input_rate_nano_per_million, Some(362_500_000));
}

#[test]
fn breakdown_bills_cached_tokens_at_input_rate_without_cached_rate() {
    let mut p = usd_pricing();
    p.cached_input_nano_per_million = None;
    let b = token_cost_breakdown(10_000, 0, 4_000, &p);
    // All 10_000 at the plain input rate.
    assert_eq!(
        b.total_nano,
        token_cost_nano(10_000, p.input_nano_per_million)
    );
    assert_eq!(b.cached_input_rate_nano_per_million, None);
}

#[test]
fn breakdown_saturates_cached_tokens_to_tokens_in() {
    let p = usd_pricing();
    // Cached saturates to all tokens_in; billed at the cached rate.
    let b = token_cost_breakdown(1_000, 0, 5_000, &p);
    assert_eq!(b.cached_tokens_in, 1_000);
    assert_eq!(
        b.total_nano,
        token_cost_nano(1_000, p.cached_input_nano_per_million.expect("seed rate"))
    );
}

// --- cost_breakdown ----------------------------------------------------------

#[test]
fn cost_breakdown_without_pricing_is_unknown_never_zero() {
    let c = cost_breakdown(8_000, 1_500, 0, 0, None);
    assert_eq!(c.status, CostStatus::Unknown);
    assert!(c.token_cost.is_none());
    assert!(c.energy_cost.is_none());
    assert!(c.currency.is_none());
    assert!(c.price_as_of.is_none());
}

#[test]
fn cost_breakdown_neuralwatt_dual_tracking() {
    let p = usd_pricing();
    let c = cost_breakdown(10_000, 2_000, 0, 18_000, Some(&p));
    assert_eq!(c.status, CostStatus::Known);
    assert_eq!(c.currency, Some(Currency::Usd));
    let t = c.token_cost.expect("token cost present");
    assert_eq!(t.total_nano, 23_500_000);
    let e = c.energy_cost.expect("energy cost present");
    assert_eq!(e.raw_energy_nano, 50_000);
    assert_eq!(e.effective_capped_nano, 50_000);
    assert!(!e.capped_by_token_cost);
}

#[test]
fn cost_breakdown_caps_energy_by_token_cost() {
    let mut p = usd_pricing();
    // $1,000,000 / kWh makes 18_000 mJ cost 5_000_000_000 nano — far above
    // the 23_500_000 nano token total.
    // $100,000 / kWh: 18_000 mJ -> 5e8 nano, far above the 23.5M token total.
    p.energy_nano_per_kwh = Some(100_000_000_000_000);
    let c = cost_breakdown(10_000, 2_000, 0, 18_000, Some(&p));
    let e = c.energy_cost.expect("energy cost present");
    // 18_000 mJ × 1e14 / 3.6e9 = 500_000_000 nano — far above the token total.
    assert_eq!(e.raw_energy_nano, 500_000_000);
    assert_eq!(e.effective_capped_nano, 23_500_000);
    assert!(e.capped_by_token_cost);
}

#[test]
fn cost_breakdown_omits_energy_without_telemetry() {
    let p = usd_pricing();
    let c = cost_breakdown(1_000, 1_000, 0, 0, Some(&p));
    assert!(c.energy_cost.is_none());
    assert_eq!(c.status, CostStatus::Known);
}

#[test]
fn cost_breakdown_omits_energy_without_rate() {
    let mut p = usd_pricing();
    p.energy_nano_per_kwh = None;
    let c = cost_breakdown(1_000, 1_000, 0, 5_000, Some(&p));
    assert!(c.energy_cost.is_none());
}

#[test]
fn cost_breakdown_is_immutable_snapshot_of_rates() {
    let p = usd_pricing();
    let c1 = cost_breakdown(1_000, 1_000, 0, 0, Some(&p));
    let mut later = p.clone();
    later.input_nano_per_million = 99_000_000_000;
    let c2 = cost_breakdown(1_000, 1_000, 0, 0, Some(&later));
    assert_ne!(c1, c2, "snapshot must reflect the rates at completion time");
    assert_eq!(c1.price_as_of, Some(p.price_as_of));
}
