// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! Background refresh of the `ai_import.ai_model_pricing` read model
//! (issue #675, design D1).
//!
//! One [`AiPricingRefreshWorker`] per process fetches four **public,
//! unauthenticated** catalogs and UPSERTs the parsed rows — never deleting
//! rows a live feed rotated out, so seeded/prior prices and their
//! `price_as_of` timestamps survive model rotation:
//!
//! - `https://api.neuralwatt.com/v1/models`   (primary for Neuralwatt)
//! - `https://openrouter.ai/api/v1/models`    (primary for OpenRouter)
//! - `https://api.eurouter.ai/api/v1/models`  (primary for EURouter)
//! - `https://models.dev/api.json`            (OpenAI, Gemini, OpenCode,
//!   OpenCode-Go; fallback for rotated models)
//!
//! Each source is fetched and parsed **independently**: one failing source
//! logs a `tracing::warn!` without aborting its siblings (spec: "Partial
//! upstream failure does not abort other pricing sources"). All four
//! endpoints are fetched through the ADR-024 hardened
//! [`build_hosted_client_with_user_agent`] transport (HTTPS-only, public-IP
//! DNS resolution + pinning, no cross-host redirects, descriptive
//! `User-Agent`, bounded body size, no credentials sent).
//!
//! Concurrency across instances is coordinated by a Postgres session
//! advisory lock (`pg_try_advisory_lock`): the instance that holds it
//! refreshes, the others skip this cycle.
//!
//! All catalog rates are parsed with **integer decimal math** — catalog
//! decimal strings/numbers are split into mantissa and exponent and scaled
//! into nano-units ($10^{-9}$ of the currency unit) with `i128` intermediates.
//! No floating-point arithmetic anywhere in this module.

use std::str::FromStr;
use std::sync::Arc;
use std::time::Duration;

use breakdown_core::ai::{
    AiModelPricingRepository, Currency, LlmProvider, ModelPricing, ModelPricingRow, PricingSource,
};
use breakdown_core::error::DomainError;
use chrono::Utc;
use futures::FutureExt;

use super::transport::build_hosted_client_with_user_agent;
use super::user_agent::resolve_user_agent;

#[cfg(test)]
#[path = "pricing_refresh_tests.rs"]
mod pricing_refresh_tests;

/// Default refresh interval: 6 hours.
pub const DEFAULT_REFRESH_INTERVAL_SECS: u64 = 21_600;
/// Refresh-interval clamp bounds (`300..=604800`).
pub const MIN_REFRESH_INTERVAL_SECS: u64 = 300;
pub const MAX_REFRESH_INTERVAL_SECS: u64 = 604_800;

/// Postgres advisory-lock key for the pricing refresh. One arbitrary constant
/// in the AI-import block (the payload-GC worker uses its own key).
const PRICING_REFRESH_ADVISORY_KEY: i64 = 723_401_772;

/// Neuralwatt's contractual energy billing: `$10.00 / kWh`, capped by the
/// same call's token cost (surge protection). The public `/models` feed does
/// not expose energy rates, so the parser attaches this stable figure to
/// every live Neuralwatt row — identical to the migration seed.
const NEURALWATT_ENERGY_NANO_PER_KWH: i64 = 10_000_000_000;

/// Refresh configuration resolved once from the environment.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PricingRefreshConfig {
    pub enabled: bool,
    pub interval: Duration,
}

impl PricingRefreshConfig {
    /// `AI_PRICING_REFRESH_ENABLED` (default `true`) and
    /// `AI_PRICING_REFRESH_INTERVAL_SECS` (default 21600 = 6 h, clamped to
    /// `300..=604800`).
    pub fn from_env() -> Self {
        let enabled = std::env::var("AI_PRICING_REFRESH_ENABLED")
            .map(|v| matches!(v.trim().to_ascii_lowercase().as_str(), "1" | "true" | "yes"))
            .unwrap_or(true);
        let secs = std::env::var("AI_PRICING_REFRESH_INTERVAL_SECS")
            .ok()
            .and_then(|v| u64::from_str(v.trim()).ok())
            .unwrap_or(DEFAULT_REFRESH_INTERVAL_SECS)
            .clamp(MIN_REFRESH_INTERVAL_SECS, MAX_REFRESH_INTERVAL_SECS);
        Self {
            enabled,
            interval: Duration::from_secs(secs),
        }
    }
}

/// Background pricing-refresh worker (design D1). Holds the Postgres pool for
/// the advisory lock and the pricing repository for the UPSERTs.
#[derive(Clone)]
pub struct AiPricingRefreshWorker {
    pool: sqlx::PgPool,
    repo: Arc<dyn AiModelPricingRepository>,
}

impl AiPricingRefreshWorker {
    pub fn new(pool: sqlx::PgPool, repo: Arc<dyn AiModelPricingRepository>) -> Self {
        Self { pool, repo }
    }

    /// Run one refresh cycle: try the advisory lock, fetch every source
    /// independently, UPSERT the merged rows. Returns whether this instance
    /// held the lock (and therefore refreshed).
    pub async fn run_once(&self) -> Result<bool, DomainError> {
        let Some(_guard) = try_advisory_lock(&self.pool).await? else {
            tracing::debug!(
                "ai-pricing-refresh: another instance holds the advisory lock; skipping cycle"
            );
            return Ok(false);
        };
        let rows = collect_catalog_rows_with(|source| async move {
            fetch_catalog_json(source.url(), source.provider()).await
        })
        .await;
        store_rows(&*self.repo, rows).await
    }

    /// Spawn the worker: one non-blocking initial refresh right after boot
    /// (spec: "initial non-blocking refresh after startup"), then one cycle
    /// per `config.interval`. The task observes the shared [shutdown signal]
    /// (`infra::ai::worker_loop::ShutdownSignal`) so graceful shutdown is
    /// prompt instead of waiting out the 10 s join budget.
    pub fn spawn(
        self,
        config: PricingRefreshConfig,
        mut shutdown: crate::ai::worker_loop::ShutdownSignal,
    ) -> tokio::task::JoinHandle<()> {
        tokio::spawn(async move {
            // Initial refresh off the boot path — a hung catalog must never
            // delay the API's readiness.
            if let Err(error) = self.run_once().await {
                tracing::warn!(%error, "ai-pricing-refresh: initial refresh failed");
            }
            let mut ticker = tokio::time::interval(config.interval);
            ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
            ticker.tick().await; // the first tick completes immediately
            loop {
                tokio::select! {
                    _ = shutdown.changed() => break,
                    _ = ticker.tick() => {}
                }
                if let Err(error) = self.run_once().await {
                    tracing::warn!(%error, "ai-pricing-refresh: refresh cycle failed");
                }
            }
        })
    }
}

/// The four live pricing sources, in refresh order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CatalogSource {
    Neuralwatt,
    OpenRouter,
    Eurouter,
    ModelsDev,
}

impl CatalogSource {
    /// The provider whose HTTP client policy and `User-Agent` apply.
    fn provider(self) -> LlmProvider {
        match self {
            Self::Neuralwatt => LlmProvider::Neuralwatt,
            Self::OpenRouter => LlmProvider::OpenRouter,
            Self::Eurouter => LlmProvider::EURouter,
            Self::ModelsDev => LlmProvider::OpenAI,
        }
    }

    /// Production catalog URL — hardcoded, curated endpoints only.
    fn url(self) -> &'static str {
        match self {
            Self::Neuralwatt => "https://api.neuralwatt.com/v1/models",
            Self::OpenRouter => "https://openrouter.ai/api/v1/models",
            Self::Eurouter => "https://api.eurouter.ai/api/v1/models",
            Self::ModelsDev => "https://models.dev/api.json",
        }
    }

    /// Parse one source's JSON payload into pricing rows.
    fn parse(self, json: &serde_json::Value) -> Result<Vec<ModelPricingRow>, DomainError> {
        match self {
            Self::Neuralwatt => parse_per_token_provider_feed(
                json,
                LlmProvider::Neuralwatt,
                Currency::Usd,
                PricingSource::ProviderLive,
                Some((NEURALWATT_ENERGY_NANO_PER_KWH, true)),
            ),
            Self::OpenRouter => parse_per_token_provider_feed(
                json,
                LlmProvider::OpenRouter,
                Currency::Usd,
                PricingSource::ProviderLive,
                None,
            ),
            Self::Eurouter => parse_per_token_provider_feed(
                json,
                LlmProvider::EURouter,
                Currency::Eur,
                PricingSource::ProviderLive,
                None,
            ),
            Self::ModelsDev => parse_models_dev(json),
        }
    }
}

/// Fetch all four sources independently and merge the parsed rows (design
/// D1: per-source warn-on-failure). A source that fails (network, HTTP
/// status, unparsable body) only warns — its seeded rows keep serving until
/// the next successful cycle. The fetch closure is injected so tests can
/// point the sources at wiremock doubles with a plain HTTP client.
pub(crate) async fn collect_catalog_rows_with<F, Fut>(fetch: F) -> Vec<ModelPricingRow>
where
    F: Fn(CatalogSource) -> Fut,
    Fut: std::future::Future<Output = Result<serde_json::Value, DomainError>>,
{
    let mut rows = Vec::new();
    for source in [
        CatalogSource::Neuralwatt,
        CatalogSource::OpenRouter,
        CatalogSource::Eurouter,
        CatalogSource::ModelsDev,
    ] {
        match fetch(source).await {
            Ok(json) => match source.parse(&json) {
                Ok(parsed) => {
                    for row in parsed {
                        // models.dev is the FALLBACK for Neuralwatt/OpenRouter:
                        // the provider's live `/v1/models` feed is primary. A
                        // fallback row must never overwrite an earlier
                        // source's row (`upsert_batch` is last-write-wins in
                        // insertion order), so duplicates are skipped.
                        let duplicate = source == CatalogSource::ModelsDev
                            && rows.iter().any(|existing: &ModelPricingRow| {
                                existing.provider == row.provider && existing.model == row.model
                            });
                        if !duplicate {
                            rows.push(row);
                        }
                    }
                }
                Err(error) => tracing::warn!(
                    %error,
                    source = ?source,
                    "ai-pricing-refresh: catalog payload unparsable; keeping seeded rows"
                ),
            },
            Err(error) => tracing::warn!(
                %error,
                source = ?source,
                "ai-pricing-refresh: catalog unavailable; keeping seeded rows"
            ),
        }
    }
    rows
}

/// Commit the merged rows; an empty merge keeps the read model untouched.
async fn store_rows(
    repo: &dyn AiModelPricingRepository,
    rows: Vec<ModelPricingRow>,
) -> Result<bool, DomainError> {
    if rows.is_empty() {
        tracing::info!(
            "ai-pricing-refresh: no live rows parsed; read model keeps its current prices"
        );
        return Ok(true);
    }
    let count = rows.len();
    repo.upsert_batch(rows).await?;
    tracing::info!(
        rows = count,
        "ai-pricing-refresh: committed live pricing upserts"
    );
    Ok(true)
}

/// Try to acquire the session-level advisory lock; `None` when another
/// instance holds it. The lock is held by the returned guard for the
/// duration of the refresh (session-scoped: released when the pooled
/// connection closes — the guard keeps a dedicated connection alive).
async fn try_advisory_lock(pool: &sqlx::PgPool) -> Result<Option<AdvisoryLockGuard>, DomainError> {
    // A dedicated connection: the session lock lives on exactly this
    // connection and is released when it is returned/closed.
    let mut conn = pool.acquire().await.map_err(|error| {
        DomainError::service_unavailable(format!("pricing refresh lock: {error}"))
    })?;
    let acquired: bool = sqlx::query_scalar("SELECT pg_try_advisory_lock($1)")
        .bind(PRICING_REFRESH_ADVISORY_KEY)
        .fetch_one(&mut *conn)
        .await
        .map_err(|error| {
            DomainError::service_unavailable(format!("pricing refresh lock: {error}"))
        })?;
    if acquired {
        Ok(Some(AdvisoryLockGuard { conn: Some(conn) }))
    } else {
        Ok(None)
    }
}

/// Holds the pooled connection the advisory lock was taken on; dropping it
/// releases the lock (connection returns to the pool for a new session).
struct AdvisoryLockGuard {
    conn: Option<sqlx::pool::PoolConnection<sqlx::Postgres>>,
}

impl Drop for AdvisoryLockGuard {
    fn drop(&mut self) {
        if let Some(mut conn) = self.conn.take() {
            // Best-effort synchronous unlock; Drop cannot await, so the
            // unlock future is polled ONCE (`now_or_never`). An idle pooled
            // connection completes it immediately; a `None` poll leaves the
            // session lock to the pool's connection lifetime (the refresh
            // path always drops the guard on an idle connection).
            match sqlx::query("SELECT pg_advisory_unlock($1)")
                .bind(PRICING_REFRESH_ADVISORY_KEY)
                .execute(&mut *conn)
                .now_or_never()
            {
                Some(Ok(_)) | None => {}
                Some(Err(e)) => {
                    tracing::warn!(error = %e, "pricing-refresh advisory unlock failed");
                }
            }
        }
    }
}

// ===========================================================================
// Catalog fetching + parsing
// ===========================================================================

/// Fetch one public catalog URL through the ADR-024 hardened hosted client.
async fn fetch_catalog_json(
    url: &str,
    provider: LlmProvider,
) -> Result<serde_json::Value, DomainError> {
    let parsed = reqwest::Url::parse(url).map_err(|error| {
        DomainError::validation(format!("invalid pricing catalog URL {url}: {error}"))
    })?;
    let host = parsed
        .host_str()
        .ok_or_else(|| DomainError::validation(format!("pricing catalog URL {url} has no host")))?;
    let http = build_hosted_client_with_user_agent(
        host,
        Duration::from_secs(30),
        resolve_user_agent(provider),
    )
    .await
    .map_err(|violation| DomainError::validation(violation.to_string()))?;
    fetch_json_with(&http, url).await
}

/// Issue the GET and decode the JSON body. Shared by production (hardened
/// per-host client) and tests (plain client against wiremock doubles — the
/// hosted regime's DNS-rebinding guard rejects loopback mock servers).
async fn fetch_json_with(
    http: &reqwest::Client,
    url: &str,
) -> Result<serde_json::Value, DomainError> {
    let response = http
        .get(url)
        .timeout(Duration::from_secs(30))
        .send()
        .await
        .map_err(|error| {
            DomainError::service_unavailable(format!("pricing catalog {url} unreachable: {error}"))
        })?;
    let status = response.status();
    if !status.is_success() {
        return Err(DomainError::service_unavailable(format!(
            "pricing catalog {url} returned HTTP {status}"
        )));
    }
    response.json().await.map_err(|error| {
        DomainError::service_unavailable(format!("invalid pricing catalog from {url}: {error}"))
    })
}

/// Parse a provider `/models` feed carrying per-token decimal rates.
pub(crate) fn parse_per_token_provider_feed(
    json: &serde_json::Value,
    provider: LlmProvider,
    currency: Currency,
    source: PricingSource,
    energy: Option<(i64, bool)>,
) -> Result<Vec<ModelPricingRow>, DomainError> {
    let entries = json
        .get("data")
        .and_then(|d| d.as_array())
        .ok_or_else(|| DomainError::service_unavailable("pricing catalog has no `data` array"))?;
    let now = Utc::now();
    let mut rows = Vec::new();
    for entry in entries {
        let Some(model) = entry.get("id").and_then(|v| v.as_str()) else {
            continue;
        };
        let Some(pricing) = entry.get("pricing") else {
            continue;
        };
        let input = pricing
            .get("prompt")
            .and_then(decimal_value_str)
            .and_then(|s| parse_decimal_to_nano_per_million_from_per_token(&s));
        let output = pricing
            .get("completion")
            .and_then(decimal_value_str)
            .and_then(|s| parse_decimal_to_nano_per_million_from_per_token(&s));
        let (Some(input), Some(output)) = (input, output) else {
            continue;
        };
        let cached = pricing
            .get("input_cache_read")
            .or_else(|| pricing.get("cache_read"))
            .and_then(decimal_value_str)
            .and_then(|s| parse_decimal_to_nano_per_million_from_per_token(&s));
        let (energy_nano_per_kwh, energy_capped_by_token) = match energy {
            Some((rate, capped)) => (Some(rate), capped),
            None => (None, false),
        };
        rows.push(ModelPricingRow {
            provider,
            model: model.to_owned(),
            pricing: ModelPricing {
                currency,
                input_nano_per_million: input,
                output_nano_per_million: output,
                cached_input_nano_per_million: cached,
                energy_nano_per_kwh,
                energy_capped_by_token,
                image_output_nano_per_million: None,
                image_nano_per_unit: None,
                pricing_source: source,
                price_as_of: now,
            },
        });
    }
    Ok(rows)
}

/// Parse the `models.dev/api.json` vendor→models catalog.
pub(crate) fn parse_models_dev(
    json: &serde_json::Value,
) -> Result<Vec<ModelPricingRow>, DomainError> {
    let vendors = json
        .as_object()
        .ok_or_else(|| DomainError::service_unavailable("models.dev catalog is not an object"))?;
    let mut rows = Vec::new();
    let now = Utc::now();
    for (vendor, vendor_obj) in vendors {
        let provider = match vendor.as_str() {
            "openai" => Some(LlmProvider::OpenAI),
            "google" => Some(LlmProvider::Gemini),
            "opencode" => Some(LlmProvider::OpenCode),
            "opencode-go" => Some(LlmProvider::OpenCodeGo),
            "neuralwatt" => Some(LlmProvider::Neuralwatt),
            "openrouter" => Some(LlmProvider::OpenRouter),
            _ => None,
        };
        let Some(provider) = provider else { continue };
        let Some(models) = vendor_obj.get("models").and_then(|m| m.as_object()) else {
            continue;
        };
        for (model, info) in models {
            let Some(cost) = info.get("cost") else {
                continue;
            };
            let input = cost
                .get("input")
                .and_then(decimal_value_str)
                .and_then(|s| parse_decimal_to_nano_per_million(&s));
            let output = cost
                .get("output")
                .and_then(decimal_value_str)
                .and_then(|s| parse_decimal_to_nano_per_million(&s));
            let (Some(input), Some(output)) = (input, output) else {
                continue;
            };
            let cached = cost
                .get("cache_read")
                .and_then(decimal_value_str)
                .and_then(|s| parse_decimal_to_nano_per_million(&s));
            let (energy_nano_per_kwh, energy_capped_by_token) =
                if provider == LlmProvider::Neuralwatt {
                    (Some(NEURALWATT_ENERGY_NANO_PER_KWH), true)
                } else {
                    (None, false)
                };
            rows.push(ModelPricingRow {
                provider,
                model: model.clone(),
                pricing: ModelPricing {
                    currency: Currency::Usd,
                    input_nano_per_million: input,
                    output_nano_per_million: output,
                    cached_input_nano_per_million: cached,
                    energy_nano_per_kwh,
                    energy_capped_by_token,
                    image_output_nano_per_million: None,
                    image_nano_per_unit: None,
                    pricing_source: PricingSource::ModelsDev,
                    price_as_of: now,
                },
            });
        }
    }
    Ok(rows)
}

/// Extract a decimal string from a JSON value (number or numeric string).
fn decimal_value_str(value: &serde_json::Value) -> Option<String> {
    match value {
        serde_json::Value::Number(n) => Some(n.to_string()),
        serde_json::Value::String(s) => Some(s.trim().to_owned()),
        _ => None,
    }
}

/// Convert a decimal string denoting a **per-1M-token** rate into
/// nano-units-per-million (half-up, `i128` intermediates, no floats).
/// Example: `"0.2925"` → `292_500_000`.
pub(crate) fn parse_decimal_to_nano_per_million(text: &str) -> Option<i64> {
    let (mantissa, exp) = parse_decimal(text)?;
    let value = scale_half_up(mantissa, 9 - exp as i32, 9)?;
    i64::try_from(value).ok()
}

/// Convert a decimal string denoting a **per-token** rate into
/// nano-units-per-million (a per-token rate × 1,000,000). Example:
/// `"0.0000002925"` → `292_500_000`.
pub(crate) fn parse_decimal_to_nano_per_million_from_per_token(text: &str) -> Option<i64> {
    let (mantissa, exp) = parse_decimal(text)?;
    let value = scale_half_up(mantissa, 15 - exp as i32, 15)?;
    i64::try_from(value).ok()
}

/// Parse a decimal string into `(mantissa, negative_exponent_digits)` where
/// the value equals `mantissa × 10^{-exp}`. Sign is rejected (rates are
/// non-negative); non-numeric input yields `None`.
pub(crate) fn parse_decimal(text: &str) -> Option<(i128, u32)> {
    let text = text.trim();
    if text.starts_with('-') {
        return None;
    }
    let text = text.strip_prefix('+').unwrap_or(text);
    let (int_part, frac_part) = match text.split_once('.') {
        Some((i, f)) => (i, f),
        None => (text, ""),
    };
    if int_part.is_empty() && frac_part.is_empty() {
        return None;
    }
    if !int_part.chars().all(|c| c.is_ascii_digit())
        || !frac_part.chars().all(|c| c.is_ascii_digit())
    {
        return None;
    }
    let mantissa: i128 = if int_part.is_empty() {
        0
    } else {
        int_part.parse().ok()?
    };
    // Cap absurdly long fractions: beyond 30 digits no nano-unit remains.
    let frac = &frac_part[..frac_part.len().min(30)];
    let mut mantissa = mantissa;
    for d in frac_part.chars().take(frac.len()) {
        mantissa = mantissa * 10 + i128::from(d.to_digit(10)?);
    }
    Some((mantissa, frac.len() as u32))
}

/// Compute `mantissa × 10^{-exp} × 10^{target}` half-up, saturating at
/// `i64::MAX`-safety boundary (`limit_bits` unused; returns i128).
fn scale_half_up(mantissa: i128, shift: i32, _target: i32) -> Option<i128> {
    let value = if shift >= 0 {
        mantissa.checked_mul(10_i128.checked_pow(shift as u32)?)?
    } else {
        let div = 10_i128.checked_pow((-shift) as u32)?;
        let q = mantissa / div;
        let r = mantissa % div;
        if r * 2 >= div { q + 1 } else { q }
    };
    if value < 0 { None } else { Some(value) }
}
