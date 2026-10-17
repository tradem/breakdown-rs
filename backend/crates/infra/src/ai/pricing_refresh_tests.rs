// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Unit tests for the pricing-refresh catalog parsers (issue #675).
//!
//! Wiremock HTTP doubles for the four live sources follow in a dedicated
//! `#[tokio::test]` harness; the pure parser paths below cover the decimal
//! scaling deterministically (AGENTS.md §4: no wall-clock gating).

use super::{
    CatalogSource as CS, fetch_json_with, parse_decimal, parse_decimal_to_nano_per_million,
    parse_decimal_to_nano_per_million_from_per_token, parse_models_dev,
    parse_per_token_provider_feed, store_rows,
};
use breakdown_core::ai::{
    AiModelPricingRepository, Currency, LlmProvider, ModelPricing, ModelPricingRow, PricingSource,
};
use breakdown_core::error::DomainError;
use std::sync::Mutex;

#[test]
fn per_million_decimal_scaling() {
    // $0.2925 / 1M (Neuralwatt flex)
    assert_eq!(
        parse_decimal_to_nano_per_million("0.2925"),
        Some(292_500_000)
    );
    // $1.45 / 1M
    assert_eq!(
        parse_decimal_to_nano_per_million("1.45"),
        Some(1_450_000_000)
    );
    // JSON number input ("292.5" per 1M)
    assert_eq!(
        parse_decimal_to_nano_per_million("292.5"),
        Some(292_500_000_000)
    );
}

#[test]
fn per_token_decimal_scaling() {
    // "0.0000002925" per token -> 292.5 nano/token -> 292_500_000 per 1M
    assert_eq!(
        parse_decimal_to_nano_per_million_from_per_token("0.0000002925"),
        Some(292_500_000)
    );
    // "0.00000145" per token -> 1_450 nano/token
    assert_eq!(
        parse_decimal_to_nano_per_million_from_per_token("0.00000145"),
        Some(1_450_000_000)
    );
}

#[test]
fn decimal_parser_rejects_garbage() {
    assert!(parse_decimal("abc").is_none());
    assert!(parse_decimal("-1.0").is_none());
    assert!(parse_decimal("").is_none());
    assert_eq!(parse_decimal("10"), Some((10, 0)));
    assert_eq!(parse_decimal("0.2925"), Some((2925, 4)));
}

#[test]
fn per_token_feed_parses_pricing_and_skips_unpriced_entries() {
    let json = serde_json::json!({
        "data": [
            {
                "id": "glm-5.3",
                "pricing": { "prompt": "0.00000145", "completion": "0.0000045" }
            },
            { "id": "no-pricing-model" },
            {
                "id": "glm-5.3-flex",
                "pricing": { "prompt": "0.0000002925", "completion": "0.000001175",
                              "input_cache_read": "0.00000003625" }
            }
        ]
    });
    let rows = parse_per_token_provider_feed(
        &json,
        LlmProvider::Neuralwatt,
        Currency::Usd,
        PricingSource::ProviderLive,
        Some((10_000_000_000, true)),
    )
    .expect("parsable feed");
    assert_eq!(rows.len(), 2, "unpriced entries are skipped");
    let glm = rows
        .iter()
        .find(|r| r.model == "glm-5.3")
        .expect("glm-5.3 row");
    assert_eq!(glm.pricing.input_nano_per_million, 1_450_000_000);
    assert_eq!(glm.pricing.output_nano_per_million, 4_500_000_000);
    assert_eq!(glm.pricing.energy_nano_per_kwh, Some(10_000_000_000));
    assert!(glm.pricing.energy_capped_by_token);
    let flex = rows
        .iter()
        .find(|r| r.model == "glm-5.3-flex")
        .expect("flex row");
    assert_eq!(flex.pricing.cached_input_nano_per_million, Some(36_250_000));
}

#[test]
fn models_dev_parses_vendor_sections() {
    let json = serde_json::json!({
        "openai": { "models": {
            "gpt-5.6-luna": { "cost": { "input": 1.25, "output": 10.0, "cache_read": 0.125 } }
        }},
        "google": { "models": {
            "gemini-3.6-flash": { "cost": { "input": 0.75, "output": 2.5 } }
        }},
        "unknown-vendor": { "models": {
            "ignored": { "cost": { "input": 1, "output": 2 } }
        }},
        "openrouter": { "models": {
            "openai/gpt-5-mini": { "cost": { "input": 0.0, "output": 0.0 } }
        }}
    });
    let rows = parse_models_dev(&json).expect("parsable catalog");
    assert_eq!(rows.len(), 3, "unknown vendors are ignored");
    let openai = rows
        .iter()
        .find(|r| r.model == "gpt-5.6-luna")
        .expect("openai row");
    assert_eq!(openai.provider, LlmProvider::OpenAI);
    assert_eq!(openai.pricing.pricing_source, PricingSource::ModelsDev);
    assert_eq!(openai.pricing.currency, Currency::Usd);
    assert_eq!(openai.pricing.input_nano_per_million, 1_250_000_000);
    assert_eq!(openai.pricing.output_nano_per_million, 10_000_000_000);
    assert_eq!(
        openai.pricing.cached_input_nano_per_million,
        Some(125_000_000)
    );
    let free = rows
        .iter()
        .find(|r| r.model == "openai/gpt-5-mini")
        .expect("openrouter row");
    assert_eq!(free.pricing.input_nano_per_million, 0);
    assert_eq!(free.pricing.output_nano_per_million, 0);
}

// ---------------------------------------------------------------------------
// Wiremock HTTP doubles (task 2.5): the four live catalog sources behind a
// plain reqwest client — the hosted regime's DNS-rebinding guard rejects
// loopback mock servers, so the status/JSON decode path is exercised through
// the shared `fetch_json_with` seam instead.
// ---------------------------------------------------------------------------

async fn fetch_source(url: &str) -> Result<serde_json::Value, DomainError> {
    fetch_json_with(&reqwest::Client::new(), url).await
}

fn neuralwatt_body() -> serde_json::Value {
    serde_json::json!({
        "data": [
            { "id": "glm-5.3", "pricing": {
                "prompt": "0.00000145", "completion": "0.0000045",
                "input_cache_read": "0.000000145" } },
            { "id": "glm-5.3-flex", "pricing": {
                "prompt": "0.0000002925", "completion": "0.000001175" } }
        ]
    })
}

fn models_dev_body() -> serde_json::Value {
    serde_json::json!({
        "openai": { "models": {
            "gpt-5.6-luna": { "cost": { "input": 1.25, "output": 10.0 } }
        }},
        "unknown-vendor": { "models": {
            "ignored": { "cost": { "input": 1, "output": 2 } }
        }}
    })
}

/// In-memory pricing repository capturing upserts (test fake, issue #675).
#[derive(Default)]
struct CollectingRepo {
    upserts: Mutex<Vec<ModelPricingRow>>,
}

#[async_trait::async_trait]
impl AiModelPricingRepository for CollectingRepo {
    async fn find_for_model(
        &self,
        _provider: LlmProvider,
        _model: &str,
    ) -> Result<Option<ModelPricing>, DomainError> {
        Ok(None)
    }

    async fn list_for_provider(
        &self,
        _provider: LlmProvider,
    ) -> Result<Vec<ModelPricingRow>, DomainError> {
        Ok(Vec::new())
    }

    async fn upsert_batch(&self, entries: Vec<ModelPricingRow>) -> Result<(), DomainError> {
        self.upserts.lock().expect("test mutex").extend(entries);
        Ok(())
    }
}

#[tokio::test]
async fn neuralwatt_source_via_wiremock_yields_priced_rows_with_energy() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .and(wiremock::matchers::path("/v1/models"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(neuralwatt_body()))
        .mount(&server)
        .await;

    let json = fetch_source(&format!("{}/v1/models", server.uri()))
        .await
        .expect("catalog fetch succeeds");
    let rows = CS::Neuralwatt
        .parse(&json)
        .expect("neuralwatt payload parses");
    assert_eq!(rows.len(), 2);
    let glm = rows.iter().find(|r| r.model == "glm-5.3").expect("glm row");
    assert_eq!(glm.provider, LlmProvider::Neuralwatt);
    assert_eq!(glm.pricing.input_nano_per_million, 1_450_000_000);
    assert_eq!(glm.pricing.cached_input_nano_per_million, Some(145_000_000));
    // Contractual energy billing attached to every live Neuralwatt row.
    assert_eq!(
        glm.pricing.energy_nano_per_kwh,
        Some(super::NEURALWATT_ENERGY_NANO_PER_KWH)
    );
    assert!(glm.pricing.energy_capped_by_token);
}

#[tokio::test]
async fn openrouter_and_eurouter_sources_map_currency_and_no_energy() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(neuralwatt_body()))
        .mount(&server)
        .await;
    let url = server.uri();

    let openrouter = CS::OpenRouter
        .parse(&fetch_source(&url).await.expect("openrouter fetch"))
        .expect("openrouter payload parses");
    assert_eq!(openrouter[0].pricing.currency, Currency::Usd);
    assert_eq!(openrouter[0].pricing.energy_nano_per_kwh, None);

    let eurouter = CS::Eurouter
        .parse(&fetch_source(&url).await.expect("eurouter fetch"))
        .expect("eurouter payload parses");
    assert_eq!(eurouter[0].pricing.currency, Currency::Eur);
    assert_eq!(
        eurouter[0].pricing.pricing_source,
        PricingSource::ProviderLive
    );
}

#[tokio::test]
async fn models_dev_source_via_wiremock_ignores_unknown_vendors() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .and(wiremock::matchers::path("/api.json"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(models_dev_body()))
        .mount(&server)
        .await;

    let json = fetch_source(&format!("{}/api.json", server.uri()))
        .await
        .expect("catalog fetch succeeds");
    let rows = CS::ModelsDev
        .parse(&json)
        .expect("models.dev payload parses");
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].provider, LlmProvider::OpenAI);
    assert_eq!(rows[0].pricing.pricing_source, PricingSource::ModelsDev);
    assert_eq!(rows[0].pricing.input_nano_per_million, 1_250_000_000);
}

#[tokio::test]
async fn http_500_maps_to_service_unavailable() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(500))
        .mount(&server)
        .await;
    let error = fetch_source(&server.uri())
        .await
        .expect_err("500 must fail");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));
}

#[tokio::test]
async fn invalid_json_body_maps_to_service_unavailable() {
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_string("<html>oops</html>"))
        .mount(&server)
        .await;
    let error = fetch_source(&server.uri())
        .await
        .expect_err("garbage body must fail");
    assert!(matches!(error, DomainError::ServiceUnavailable { .. }));
}

#[tokio::test]
async fn collect_cycle_skips_failing_sources_and_keeps_healthy_ones() {
    // One healthy per-token source, one failing HTTP source, one garbage
    // source, one healthy models.dev source — the merge keeps the healthy
    // rows (per-source warn-on-failure, design D1).
    let ok = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(neuralwatt_body()))
        .mount(&ok)
        .await;
    let bad = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(503))
        .mount(&bad)
        .await;
    let garbage = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_string("not json"))
        .mount(&garbage)
        .await;
    let models = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(models_dev_body()))
        .mount(&models)
        .await;

    let ok_url = ok.uri();
    let bad_url = bad.uri();
    let garbage_url = garbage.uri();
    let models_url = models.uri();
    let rows = super::collect_catalog_rows_with(|source| {
        let url = match source {
            CS::Neuralwatt => ok_url.clone(),
            CS::OpenRouter => bad_url.clone(),
            CS::Eurouter => garbage_url.clone(),
            CS::ModelsDev => models_url.clone(),
        };
        async move { fetch_source(&url).await }
    })
    .await;
    assert_eq!(
        rows.len(),
        3,
        "the two healthy sources yield rows; the failing ones only warn"
    );
    assert!(rows.iter().all(|r| r.provider != LlmProvider::OpenRouter));
}

#[tokio::test]
async fn store_rows_upserts_merged_rows_and_empty_merge_is_noop() {
    let repo = CollectingRepo::default();
    let server = wiremock::MockServer::start().await;
    wiremock::Mock::given(wiremock::matchers::method("GET"))
        .respond_with(wiremock::ResponseTemplate::new(200).set_body_json(neuralwatt_body()))
        .mount(&server)
        .await;
    let url = server.uri();
    let rows = super::collect_catalog_rows_with(move |source| {
        let url = if source == CS::Neuralwatt {
            url.clone()
        } else {
            // Unroutable port: the failing sources only warn.
            "http://127.0.0.1:1/v1/models".to_owned()
        };
        async move { fetch_source(&url).await }
    })
    .await;
    assert_eq!(rows.len(), 2);
    store_rows(&repo, rows).await.expect("upsert succeeds");
    assert_eq!(repo.upserts.lock().expect("test mutex").len(), 2);

    // Empty merge keeps the read model untouched (no upsert call).
    let empty = store_rows(&repo, Vec::new()).await;
    assert!(matches!(empty, Ok(true)));
    assert_eq!(repo.upserts.lock().expect("test mutex").len(), 2);
}
