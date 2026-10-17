// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

//! PostgreSQL read-model adapter over `ai_import.ai_model_pricing`
//! (issue #675). Consumed by the API model-list endpoint (`list_for_provider`),
//! the import workers (`find_for_model`), and the pricing refresh worker
//! (`upsert_batch` — UPSERT-only, never deletes rotated-out rows).

use async_trait::async_trait;
use breakdown_core::ai::{
    AiModelPricingRepository, Currency, LlmProvider, ModelPricing, ModelPricingRow, PricingSource,
};
use breakdown_core::error::DomainError;
use chrono::{DateTime, Utc};
use sqlx::{PgPool, Row};

/// Parse a pricing row's `currency` text. Unknown values are a projection
/// integrity defect (the CHECK constraint admits only USD/EUR) — surfaced as
/// a validation error, not a panic.
fn parse_currency(value: String) -> Result<Currency, DomainError> {
    match value.as_str() {
        "USD" => Ok(Currency::Usd),
        "EUR" => Ok(Currency::Eur),
        other => Err(DomainError::validation(format!(
            "unknown ai_model_pricing currency {other}"
        ))),
    }
}

/// Parse a pricing row's `pricing_source` text (CHECK-constrained).
fn parse_pricing_source(value: String) -> Result<PricingSource, DomainError> {
    match value.as_str() {
        "curated_seed" => Ok(PricingSource::CuratedSeed),
        "provider_live" => Ok(PricingSource::ProviderLive),
        "models_dev" => Ok(PricingSource::ModelsDev),
        other => Err(DomainError::validation(format!(
            "unknown ai_model_pricing pricing_source {other}"
        ))),
    }
}

/// PostgreSQL implementation of [`AiModelPricingRepository`]. All statements
/// are static literals with bound values (AGENTS.md §3, no string
/// interpolation).
#[derive(Clone, Debug)]
pub struct PgAiModelPricingRepository {
    pool: PgPool,
}

impl PgAiModelPricingRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }
}

#[async_trait]
impl AiModelPricingRepository for PgAiModelPricingRepository {
    async fn find_for_model(
        &self,
        provider: LlmProvider,
        model: &str,
    ) -> Result<Option<ModelPricing>, DomainError> {
        let row = sqlx::query_as::<_, PricingRecord>(
            r#"
            SELECT currency, input_nano_per_million, output_nano_per_million,
                   cached_input_nano_per_million, energy_nano_per_kwh,
                   energy_capped_by_token, image_output_nano_per_million,
                   image_nano_per_unit, pricing_source, price_as_of
            FROM ai_import.ai_model_pricing
            WHERE provider = $1 AND model = $2
            "#,
        )
        .bind(provider.as_str())
        .bind(model)
        .fetch_optional(&self.pool)
        .await
        .map_err(map_sqlx_error)?;

        row.map(PricingRecord::into_model_pricing).transpose()
    }

    async fn list_for_provider(
        &self,
        provider: LlmProvider,
    ) -> Result<Vec<ModelPricingRow>, DomainError> {
        let rows = sqlx::query(
            r#"
            SELECT model,
                   currency, input_nano_per_million, output_nano_per_million,
                   cached_input_nano_per_million, energy_nano_per_kwh,
                   energy_capped_by_token, image_output_nano_per_million,
                   image_nano_per_unit, pricing_source, price_as_of
            FROM ai_import.ai_model_pricing
            WHERE provider = $1
            ORDER BY model
            "#,
        )
        .bind(provider.as_str())
        .fetch_all(&self.pool)
        .await
        .map_err(map_sqlx_error)?;

        rows.into_iter()
            .map(|row| {
                let pricing = PricingRecord {
                    currency: row.try_get("currency").map_err(map_sqlx_error)?,
                    input_nano_per_million: row
                        .try_get("input_nano_per_million")
                        .map_err(map_sqlx_error)?,
                    output_nano_per_million: row
                        .try_get("output_nano_per_million")
                        .map_err(map_sqlx_error)?,
                    cached_input_nano_per_million: row
                        .try_get("cached_input_nano_per_million")
                        .map_err(map_sqlx_error)?,
                    energy_nano_per_kwh: row
                        .try_get("energy_nano_per_kwh")
                        .map_err(map_sqlx_error)?,
                    energy_capped_by_token: row
                        .try_get("energy_capped_by_token")
                        .map_err(map_sqlx_error)?,
                    image_output_nano_per_million: row
                        .try_get("image_output_nano_per_million")
                        .map_err(map_sqlx_error)?,
                    image_nano_per_unit: row
                        .try_get("image_nano_per_unit")
                        .map_err(map_sqlx_error)?,
                    pricing_source: row.try_get("pricing_source").map_err(map_sqlx_error)?,
                    price_as_of: row.try_get("price_as_of").map_err(map_sqlx_error)?,
                };
                Ok(ModelPricingRow {
                    provider,
                    model: row.try_get("model").map_err(map_sqlx_error)?,
                    pricing: pricing.into_model_pricing()?,
                })
            })
            .collect()
    }

    async fn upsert_batch(&self, entries: Vec<ModelPricingRow>) -> Result<(), DomainError> {
        if entries.is_empty() {
            return Ok(());
        }
        let mut tx = self.pool.begin().await.map_err(map_sqlx_error)?;
        for entry in entries {
            sqlx::query(
                r#"
                INSERT INTO ai_import.ai_model_pricing
                    (provider, model, currency, input_nano_per_million,
                     output_nano_per_million, cached_input_nano_per_million,
                     energy_nano_per_kwh, energy_capped_by_token,
                     image_output_nano_per_million, image_nano_per_unit,
                     pricing_source, price_as_of)
                VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
                ON CONFLICT (provider, model) DO UPDATE SET
                    currency = EXCLUDED.currency,
                    input_nano_per_million = EXCLUDED.input_nano_per_million,
                    output_nano_per_million = EXCLUDED.output_nano_per_million,
                    cached_input_nano_per_million = EXCLUDED.cached_input_nano_per_million,
                    energy_nano_per_kwh = EXCLUDED.energy_nano_per_kwh,
                    energy_capped_by_token = EXCLUDED.energy_capped_by_token,
                    image_output_nano_per_million = EXCLUDED.image_output_nano_per_million,
                    image_nano_per_unit = EXCLUDED.image_nano_per_unit,
                    pricing_source = EXCLUDED.pricing_source,
                    price_as_of = EXCLUDED.price_as_of,
                    updated_at = now()
                "#,
            )
            .bind(entry.provider.as_str())
            .bind(&entry.model)
            .bind(entry.pricing.currency.as_str())
            .bind(entry.pricing.input_nano_per_million)
            .bind(entry.pricing.output_nano_per_million)
            .bind(entry.pricing.cached_input_nano_per_million)
            .bind(entry.pricing.energy_nano_per_kwh)
            .bind(entry.pricing.energy_capped_by_token)
            .bind(entry.pricing.image_output_nano_per_million)
            .bind(entry.pricing.image_nano_per_unit)
            .bind(pricing_source_str(entry.pricing.pricing_source))
            .bind(entry.pricing.price_as_of)
            .execute(&mut *tx)
            .await
            .map_err(map_sqlx_error)?;
        }
        tx.commit().await.map_err(map_sqlx_error)
    }
}

fn pricing_source_str(source: PricingSource) -> &'static str {
    match source {
        PricingSource::CuratedSeed => "curated_seed",
        PricingSource::ProviderLive => "provider_live",
        PricingSource::ModelsDev => "models_dev",
    }
}

fn map_sqlx_error(error: sqlx::Error) -> DomainError {
    DomainError::service_unavailable(format!("ai_model_pricing read model unavailable: {error}"))
}

/// sqlx `query_as` record mirroring one `ai_model_pricing` row.
#[derive(sqlx::FromRow)]
struct PricingRecord {
    currency: String,
    input_nano_per_million: i64,
    output_nano_per_million: i64,
    cached_input_nano_per_million: Option<i64>,
    energy_nano_per_kwh: Option<i64>,
    energy_capped_by_token: bool,
    image_output_nano_per_million: Option<i64>,
    image_nano_per_unit: Option<i64>,
    pricing_source: String,
    price_as_of: DateTime<Utc>,
}

impl PricingRecord {
    fn into_model_pricing(self) -> Result<ModelPricing, DomainError> {
        Ok(ModelPricing {
            currency: parse_currency(self.currency)?,
            input_nano_per_million: self.input_nano_per_million,
            output_nano_per_million: self.output_nano_per_million,
            cached_input_nano_per_million: self.cached_input_nano_per_million,
            energy_nano_per_kwh: self.energy_nano_per_kwh,
            energy_capped_by_token: self.energy_capped_by_token,
            image_output_nano_per_million: self.image_output_nano_per_million,
            image_nano_per_unit: self.image_nano_per_unit,
            pricing_source: parse_pricing_source(self.pricing_source)?,
            price_as_of: self.price_as_of,
        })
    }
}
