// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)
// Co-authored-by: gpt-5.6-luna (opencode-go)
// Co-authored-by: deepseek-v4-flash (opencode-go)
// Co-authored-by: deepseek-v4.1-flash (neuralwatt)
// Co-authored-by: qwen3.8-flash (opencode-go)

use std::time::Duration;

use async_trait::async_trait;
use breakdown_core::ai::{
    CuratedLlmProvider, LlmCallOutcome, LlmCallUsage, LlmChatRequest, LlmClient, LlmProvider,
    ScriptContext,
};
use breakdown_core::error::DomainError;
use breakdown_core::settings::SecretValue;
use reqwest::StatusCode;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::json;

use super::CuratedProviderUrls;
use super::transport::build_hosted_client_with_user_agent;
use super::user_agent::resolve_user_agent;

#[cfg(test)]
#[path = "client_tests.rs"]
mod client_tests;

/// OpenAI-compatible `/chat/completions` adapter. The provider URL is chosen
/// exclusively from the curated provider registry; callers cannot supply one.
pub struct OpenAiCompatibleChatClient {
    http: reqwest::Client,
    provider: LlmProvider,
    api_key: SecretValue,
    timeout: Duration,
}

/// Output-token budget growth per truncation retry (doubling) and the number
/// of bounded retries granted when a provider reports a token-ceiling
/// truncation (`finish_reason: "length"`). Together they bound the worst-case
/// paid cost of one `chat_constrained` call: at most
/// `MAX_TRUNCATION_RETRIES + 1` attempts with budgets
/// `B, B·2, …, B·2^MAX_TRUNCATION_RETRIES` (saturating at the `u32` ceiling) —
/// mirroring the Ollama adapter's bounded parse-or-retry. Without the growth a
/// response cut off at the caller's `max_tokens` budget failed permanently
/// although a larger budget would have succeeded (nightly AI Import smoke
/// 2026-08-13: `EOF while parsing an object at line 1 column 1158`).
const TRUNCATION_RETRY_BUDGET_GROWTH: u32 = 2;
const MAX_TRUNCATION_RETRIES: u32 = 2;

impl OpenAiCompatibleChatClient {
    /// Reject Ollama in this client: its curated base URL is plain HTTP and
    /// sending vaulted bearer credentials there would leak them (CWE-319).
    /// Ollama must be routed through `OllamaChatClient`.
    fn reject_ollama(provider: LlmProvider) -> Result<(), DomainError> {
        if provider == LlmProvider::Ollama {
            return Err(DomainError::validation(
                "Ollama must be routed through OllamaChatClient — the \
             OpenAI-compatible client would send bearer auth to its HTTP \
             base URL"
                    .to_owned(),
            ));
        }
        Ok(())
    }

    pub async fn new(
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        Self::reject_ollama(provider)?;
        if api_key.trim().is_empty() {
            return Err(DomainError::validation("LLM API key must not be empty"));
        }
        // Transport policy (issue #170): HTTPS-only, same-origin redirects
        // AND a DNS-resolution guard — the curated provider hostname must
        // resolve exclusively to globally routable addresses, which are then
        // pinned for the whole request chain (initial request + same-origin
        // redirects). Vaulted bearer credentials therefore never reach an
        // internal service, even if the hostname text is allowlisted but
        // resolves privately (DNS rebinding).
        let host = Self::hosted_origin_host(provider)?;
        let http =
            build_hosted_client_with_user_agent(&host, timeout, resolve_user_agent(provider))
                .await
                .map_err(|violation| DomainError::validation(violation.to_string()))?;
        Ok(Self {
            http,
            provider,
            api_key: SecretValue::new(api_key),
            timeout,
        })
    }

    /// Host of the curated provider base URL. The base URLs are static
    /// literals under our control; a parse failure is a programming error and
    /// surfaces as a validation error (fail closed, no panic).
    fn hosted_origin_host(provider: LlmProvider) -> Result<String, DomainError> {
        let base = CuratedProviderUrls::base_url(provider);
        let url = reqwest::Url::parse(base).map_err(|error| {
            DomainError::validation(format!(
                "invalid curated base URL for {provider:?}: {error}"
            ))
        })?;
        url.host_str().map(str::to_owned).ok_or_else(|| {
            DomainError::validation(format!("curated base URL for {provider:?} has no host"))
        })
    }

    /// Test seam: inject a prebuilt client while still enforcing the request
    /// deadline per call (the injected client may not carry one). The caller
    /// owns transport configuration when injecting; the production path
    /// ([`Self::new`]) applies the issue #170 redirect policy automatically.
    pub fn with_http(
        http: reqwest::Client,
        provider: LlmProvider,
        api_key: String,
        timeout: Duration,
    ) -> Result<Self, DomainError> {
        Self::reject_ollama(provider)?;
        if api_key.trim().is_empty() {
            return Err(DomainError::validation("LLM API key must not be empty"));
        }
        Ok(Self {
            http,
            provider,
            api_key: SecretValue::new(api_key),
            timeout,
        })
    }

    fn endpoint(&self) -> String {
        format!(
            "{}/chat/completions",
            CuratedProviderUrls::base_url(self.provider)
        )
    }

    async fn request(
        &self,
        req: &LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        let schema = req
            .response_schema
            .clone()
            .unwrap_or_else(|| schemars::schema_for!(ScriptContextSchema).to_value());
        let mut budget = req.max_tokens;
        let mut truncation_retries = MAX_TRUNCATION_RETRIES;
        // Usage accumulates across every paid HTTP response, including the
        // discarded responses of truncation retries (issue #675) — the
        // provider billed those tokens too.
        let mut total_usage = LlmCallUsage::default();
        loop {
            let body = ChatCompletionRequest {
                model: req.model.clone(),
                // The configured prompt (instructions) is carried in a system
                // message; the source document is untrusted user data in its own
                // message so it cannot override prompt directives via delimiters.
                messages: vec![
                    ChatMessage {
                        role: "system".to_owned(),
                        content: req.prompt.clone(),
                    },
                    ChatMessage {
                        role: "user".to_owned(),
                        content: format!("<context>\n{}\n</context>", req.source_text),
                    },
                ],
                max_tokens: budget,
                response_format: Some(json!({
                    "type": "json_schema",
                    "json_schema": {
                        "name": "script_context",
                        "strict": true,
                        "schema": schema,
                    }
                })),
            };
            let response = self
                .http
                .post(self.endpoint())
                .timeout(self.timeout)
                .bearer_auth(self.api_key.as_str())
                .json(&body)
                .send()
                .await
                .map_err(classify_transport_error)?;
            let status = response.status();
            if !status.is_success() {
                return Err(classify_http_status(status));
            }
            let envelope = response
                .json::<ChatCompletionResponse>()
                .await
                .map_err(|error| {
                    DomainError::validation(format!("invalid LLM response: {error}"))
                })?;
            total_usage.accumulate(envelope.usage());
            let choice = envelope
                .choices
                .first()
                .ok_or_else(|| DomainError::validation("LLM response contained no choices"))?;
            let content = choice
                .message
                .content
                .as_deref()
                .ok_or_else(|| DomainError::validation("LLM response contained no content"))?;
            match serde_json::from_str(content) {
                Ok(context) => {
                    return Ok(LlmCallOutcome::new(context, total_usage));
                }
                Err(error) => {
                    match next_truncation_budget(
                        choice.finish_reason.as_deref(),
                        budget,
                        truncation_retries,
                    ) {
                        Some(grown) => {
                            budget = grown;
                            truncation_retries -= 1;
                        }
                        None => {
                            let truncated = choice.finish_reason.as_deref() == Some("length");
                            let suffix = if truncated {
                                " (response truncated at the output-token budget \
                                 after bounded retries)"
                            } else {
                                " (after bounded retries with a grown output-token \
                                 budget)"
                            };
                            return Err(DomainError::validation(format!(
                                "LLM JSON did not match ScriptContext: {error}{suffix}"
                            )));
                        }
                    }
                }
            }
        }
    }
}

#[async_trait]
impl LlmClient for OpenAiCompatibleChatClient {
    async fn chat_constrained(
        &self,
        req: LlmChatRequest,
    ) -> Result<LlmCallOutcome<ScriptContext>, DomainError> {
        if req.provider != self.provider {
            return Err(DomainError::validation(
                "LLM request provider does not match configured client",
            ));
        }
        self.request(&req).await
    }
}

#[derive(Debug, Serialize)]
struct ChatCompletionRequest {
    model: String,
    messages: Vec<ChatMessage>,
    max_tokens: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    response_format: Option<serde_json::Value>,
}

#[derive(Debug, Serialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Debug, Deserialize)]
struct ChatCompletionResponse {
    choices: Vec<ChatChoice>,
    /// Token usage reported by the provider (issue #675). Absent on some
    /// providers/streams — tolerated, usage stays at the accumulated zeros.
    #[serde(default)]
    usage: Option<ChatUsage>,
    /// Hardware energy telemetry reported by Neuralwatt (issue #675).
    #[serde(default)]
    energy: Option<ChatEnergy>,
}

impl ChatCompletionResponse {
    /// Extract the `LlmCallUsage` of this one response (zeros when the
    /// provider reports nothing).
    fn usage(&self) -> LlmCallUsage {
        let tokens_in = self.usage.as_ref().and_then(|u| u.prompt_tokens);
        let tokens_out = self.usage.as_ref().and_then(|u| u.completion_tokens);
        let cached_tokens_in = self
            .usage
            .as_ref()
            .and_then(|u| u.prompt_tokens_details.as_ref())
            .and_then(|d| d.cached_tokens);
        let energy_millijoules = self
            .energy
            .as_ref()
            .and_then(parse_energy_millijoules)
            .unwrap_or(0);
        LlmCallUsage {
            tokens_in: tokens_in.unwrap_or(0),
            tokens_out: tokens_out.unwrap_or(0),
            cached_tokens_in: cached_tokens_in.unwrap_or(0),
            energy_millijoules,
        }
    }
}

/// OpenAI-compatible `usage` object.
#[derive(Debug, Deserialize)]
struct ChatUsage {
    #[serde(default)]
    prompt_tokens: Option<u64>,
    #[serde(default)]
    completion_tokens: Option<u64>,
    #[serde(default)]
    prompt_tokens_details: Option<ChatPromptTokensDetails>,
}

#[derive(Debug, Deserialize)]
struct ChatPromptTokensDetails {
    #[serde(default)]
    cached_tokens: Option<u64>,
}

/// Neuralwatt hardware-energy telemetry. Values are JSON numbers or numeric
/// strings in joules or kWh; parsed with integer decimal math (no floats).
#[derive(Debug, Deserialize)]
struct ChatEnergy {
    #[serde(default)]
    energy_joules: Option<serde_json::Value>,
    #[serde(default)]
    energy_kwh: Option<serde_json::Value>,
}

/// Parse a hardware-energy value into millijoules with integer arithmetic.
/// Joules take precedence over kWh (`1 kWh = 3.6 × 10^9 mJ`). Accepts JSON
/// numbers and numeric strings, both integral and fractional decimal.
fn parse_energy_millijoules(energy: &ChatEnergy) -> Option<u64> {
    if let Some(joules) = &energy.energy_joules {
        return parse_decimal_scaled(joules, JOULES_TO_MILLIJOULES);
    }
    parse_decimal_scaled(energy.energy_kwh.as_ref()?, KWH_TO_MILLIJOULES)
}

/// `1 J = 1_000 mJ`.
const JOULES_TO_MILLIJOULES: i128 = 1_000;
/// `1 kWh = 3.6 × 10^9 mJ`.
const KWH_TO_MILLIJOULES: i128 = 3_600_000_000;

/// Convert a JSON number-or-string decimal (optional `e±N` exponent —
/// serde_json renders small floats in scientific notation, e.g. `5e-6`)
/// into `value × factor` millijoules, half-up rounded, with `i128`
/// intermediate math (no floats). The FULL fraction participates in the
/// scaling: quantizing to three fraction digits before multiplying by a
/// large factor (kWh = 3.6e9) would round a realistic 0.000005 kWh Neuralwatt
/// reading (18 000 mJ) down to zero. Returns `None` for non-numeric input —
/// callers treat that as "no telemetry reported", never as zero.
fn parse_decimal_scaled(value: &serde_json::Value, factor: i128) -> Option<u64> {
    let text = match value {
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::String(s) => s.trim().to_owned(),
        _ => return None,
    };
    let (mantissa_text, exp) = match text.split_once(['e', 'E']) {
        Some((mantissa, exponent)) => (mantissa, exponent.parse::<i32>().ok()?),
        None => (text.as_str(), 0),
    };
    let (negative, digits) = match mantissa_text.strip_prefix('-') {
        Some(rest) => (true, rest),
        None => (false, mantissa_text),
    };
    let (int_part, frac_part) = match digits.split_once('.') {
        Some((i, f)) => (i, f),
        None => (digits, ""),
    };
    if int_part.is_empty() && frac_part.is_empty() {
        return None;
    }
    if !int_part.chars().all(|c| c.is_ascii_digit())
        || !frac_part.chars().all(|c| c.is_ascii_digit())
    {
        return None;
    }
    let int_val: i128 = if int_part.is_empty() {
        0
    } else {
        int_part.parse().ok()?
    };
    // Exact value = mantissa × 10^exp × factor / 10^frac_len, half-up
    // rounded to a whole millijoule count. A positive exponent shifts the
    // decimal point before the division, so `5e-6` kWh = 18 000 mJ comes
    // out exactly instead of being quantized to zero.
    let mut mantissa = int_val;
    for digit in frac_part.chars() {
        mantissa = mantissa
            .checked_mul(10)?
            .checked_add(i128::from(digit.to_digit(10)?))?;
    }
    let scaled = if exp > 0 {
        mantissa
            .checked_mul(10_i128.checked_pow(u32::try_from(exp).ok()?)?)?
            .checked_mul(factor)?
    } else {
        mantissa.checked_mul(factor)?
    };
    let den_shift = if exp < 0 {
        // `unsigned_abs()` cannot overflow (unlike `-exp` at `i32::MIN`) —
        // `exp` comes from provider-controlled text. The checked add/pow
        // turn an absurd shift into `None` ("no telemetry"), never a panic.
        exp.unsigned_abs()
            .checked_add(u32::try_from(frac_part.len()).ok()?)?
    } else {
        frac_part.len() as u32
    };
    let den = 10_i128.checked_pow(den_shift)?;
    let (quotient, remainder) = (scaled / den, scaled % den);
    let total = if remainder * 2 >= den {
        quotient + 1
    } else {
        quotient
    };
    if negative {
        return None;
    }
    u64::try_from(total).ok()
}

#[derive(Debug, Deserialize)]
struct ChatChoice {
    message: ChatMessageResponse,
    /// Provider-side stop reason. `Some("length")` signals the response was
    /// cut off at the `max_tokens` ceiling — the JSON payload is typically
    /// truncated mid-object and must be retried with a grown budget.
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ChatMessageResponse {
    content: Option<String>,
}

/// Infra-local schema mirror. Core remains independent of schemars while the
/// wire schema stays statically derived from the same JSON shape.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct ScriptContextSchema {
    title: Option<String>,
    scenes: Vec<DraftSceneSchema>,
    uncertainties: Vec<UncertaintySchema>,
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct DraftSceneSchema {
    draft_ref: String,
    scene_number: Option<u32>,
    location: Option<String>,
    mood: Option<String>,
    summary: Option<String>,
    script_day: Option<String>,
    characters: Vec<String>,
    /// Costumes worn by characters of THIS scene. Empty when the block states no
    /// clothing at all — never omit the field, and never invent an entry to fill
    /// it. `strict` schema mode requires the property, so a scene without
    /// costuming answers with `[]`.
    costumes: Vec<DraftCostumeSchema>,
}

/// Provider-facing mirror of [`breakdown_core::ai::DraftCostume`]. One entry per
/// garment or accessory the text states for one named character.
#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct DraftCostumeSchema {
    /// The character this costume belongs to. MUST be spelled as in this scene's
    /// `characters`; an entry naming anyone else is dropped by the server.
    character_name: String,
    /// The garment/accessory description in the script's own wording. Do not
    /// paraphrase, translate, or summarise it, and do not move it into `summary`.
    description: String,
    /// A verbatim fragment of the supplied text this entry came from. The server
    /// checks that the fragment occurs in the block and drops the entry when it
    /// does not, so a paraphrase fails and the costume is lost.
    source_quote: String,
}

#[derive(Debug, Serialize, Deserialize, JsonSchema)]
struct UncertaintySchema {
    scene_index: usize,
    field: String,
    note: String,
    suggested_value: Option<String>,
}

pub fn classify_http_status(status: StatusCode) -> DomainError {
    if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
        DomainError::service_unavailable(format!("LLM provider returned HTTP {status}"))
    } else if status.is_client_error() {
        DomainError::validation(format!("LLM provider rejected request with HTTP {status}"))
    } else {
        DomainError::validation(format!("unexpected LLM provider HTTP status {status}"))
    }
}

pub fn classify_transport_error(error: reqwest::Error) -> DomainError {
    if error.is_timeout() || error.is_connect() {
        DomainError::service_unavailable(format!("LLM provider transport unavailable: {error}"))
    } else if error.is_redirect() {
        // Deterministic policy rejection (issue #170): retrying cannot change
        // the outcome, so it is a permanent validation failure.
        DomainError::validation(format!(
            "LLM provider redirect rejected by transport policy: {error}"
        ))
    } else {
        DomainError::validation(format!("LLM provider request failed: {error}"))
    }
}

/// Output-token budget for the next truncation retry, or `None` when the
/// response must fail permanently. Only a provider-reported token-ceiling
/// truncation (`finish_reason == "length"`) qualifies for a retry: a
/// well-formed JSON that decodes to the wrong shape (`finish_reason ==
/// "stop"`) is not retried, because re-paying a paid LLM call on arbitrary
/// malformed output is a cost risk, not a recovery. Retries are bounded by
/// `truncation_retries_left`, so the worst-case spend of one call stays
/// bounded (see [`MAX_TRUNCATION_RETRIES`]).
fn next_truncation_budget(
    finish_reason: Option<&str>,
    budget: u32,
    truncation_retries_left: u32,
) -> Option<u32> {
    // Any malformed response may be retryable, not only a provider-confirmed
    // `finish_reason: "length"`. Gateways and routers routinely cut a body
    // short while reporting `stop` (or omitting the field entirely), and a
    // strict `== Some("length")` then classified a truncated answer as
    // permanent and dead-lettered the job after ONE attempt — observed live
    // against eurouter: "LLM JSON did not match ScriptContext: EOF while
    // parsing a string at line 1 column 1437" with no
    // "after bounded retries" suffix, i.e. the growth path was never taken.
    //
    // The bound is unchanged (MAX_TRUNCATION_RETRIES attempts, budget x2), so
    // a genuinely malformed response still fails after a fixed, bounded number
    // of paid retries instead of retrying forever.
    let _ = finish_reason;
    if truncation_retries_left > 0 {
        Some(budget.saturating_mul(TRUNCATION_RETRY_BUDGET_GROWTH))
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decimal_scaled_keeps_sub_milli_kwh_precision() {
        // The spec example: 0.000005 kWh (a realistic Neuralwatt reading) is
        // exactly 18 000 mJ — the old three-digit pre-rounding returned 0.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.000005"), KWH_TO_MILLIJOULES),
            Some(18_000)
        );
        // Joules stay exact.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("18"), JOULES_TO_MILLIJOULES),
            Some(18_000)
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!(4.2), JOULES_TO_MILLIJOULES),
            Some(4_200)
        );
    }

    #[test]
    fn decimal_scaled_accepts_scientific_notation() {
        // serde_json renders small floats via ryu as `5e-6` — the digit
        // check must not reject the exponent form.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!(5e-6), KWH_TO_MILLIJOULES),
            Some(18_000)
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("5E-6"), KWH_TO_MILLIJOULES),
            Some(18_000)
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("1.5e3"), JOULES_TO_MILLIJOULES),
            Some(1_500_000)
        );
    }

    #[test]
    fn decimal_scaled_rounds_half_up_and_rejects_non_numeric() {
        // 0.5 mJ (in joules) — the exact half boundary rounds UP.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.0005"), JOULES_TO_MILLIJOULES),
            Some(1)
        );
        // 0.4 mJ rounds DOWN.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.0004"), JOULES_TO_MILLIJOULES),
            Some(0)
        );
        // 3.6 mJ (1e-9 kWh) rounds half-up to 4.
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("0.000000001"), KWH_TO_MILLIJOULES),
            Some(4)
        );
        // `i32::MIN` exponent: `-exp` would overflow-panic in debug builds —
        // the parse must degrade to `None` instead (regression for the
        // provider-controlled-exponent hardening).
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("-1e-2147483648"), JOULES_TO_MILLIJOULES),
            None
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("-1e2147483647"), JOULES_TO_MILLIJOULES),
            None
        );
        // Negative telemetry is not a valid reading (never a negative cost).
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!(-1), JOULES_TO_MILLIJOULES),
            None
        );
        assert_eq!(
            parse_decimal_scaled(&serde_json::json!("not-a-number"), JOULES_TO_MILLIJOULES),
            None
        );
    }

    #[test]
    fn truncated_response_grows_budget_while_retries_remain() {
        assert_eq!(next_truncation_budget(Some("length"), 2048, 2), Some(4096));
        assert_eq!(next_truncation_budget(Some("length"), 4096, 1), Some(8192));
    }

    #[test]
    fn truncation_without_retries_left_fails_permanently() {
        assert_eq!(next_truncation_budget(Some("length"), 2048, 0), None);
    }

    #[test]
    fn unconfirmed_truncation_is_still_retried_within_the_bound() {
        // Gateways/routers report a cut-off body as `stop` (or omit the field)
        // instead of `length`. Live case against eurouter: "EOF while parsing a
        // string at line 1 column 1437" dead-lettered after ONE attempt because
        // the strict `== Some("length")` guard never grew the budget. The
        // response may be truncated regardless of what the provider claims, so
        // the bound — not the reported reason — decides retryability.
        assert_eq!(next_truncation_budget(Some("stop"), 2048, 2), Some(4096));
        assert_eq!(next_truncation_budget(None, 2048, 2), Some(4096));
        assert_eq!(
            next_truncation_budget(Some("content_filter"), 2048, 1),
            Some(4096)
        );
    }

    #[test]
    fn a_genuinely_malformed_response_still_stops_at_the_bound() {
        // The retry growth is bounded: a permanently malformed answer (e.g. a
        // content-filtered one) must fail after the fixed attempt count rather
        // than re-paying the call forever.
        for reason in [Some("stop"), None, Some("content_filter"), Some("length")] {
            assert_eq!(
                next_truncation_budget(reason, 8192, 0),
                None,
                "exhausted budget must fail for {reason:?}"
            );
        }
    }

    #[test]
    fn truncation_budget_growth_saturates_at_u32_ceiling() {
        // `saturating_mul` keeps the budget growth total even at the ceiling.
        assert_eq!(
            next_truncation_budget(Some("length"), u32::MAX, 1),
            Some(u32::MAX)
        );
    }

    /// The mirror the provider is handed must carry the costume list, or the model
    /// has nowhere to put a costume it recognised and `serde` drops it silently —
    /// the exact failure that produced 0 costumes from a script that names them.
    /// schemars 1.x emits `$defs` (draft 2020-12); older releases emitted
    /// `definitions`. Resolve either so the assertions below test the contract
    /// and not the generator's dialect.
    fn defs(value: &serde_json::Value) -> &serde_json::Value {
        value
            .get("$defs")
            .or_else(|| value.get("definitions"))
            .unwrap_or_else(|| panic!("no type definitions in the emitted schema: {value}"))
    }

    #[test]
    fn provider_schema_mirrors_the_costume_fields() {
        let schema = schemars::schema_for!(ScriptContextSchema);
        let value = serde_json::to_value(&schema).unwrap();
        let scene = &defs(&value)["DraftSceneSchema"]["properties"];
        assert!(
            scene["costumes"].is_object(),
            "the schema sent to the provider must carry `costumes`, got {scene:?}"
        );
        let costume = &defs(&value)["DraftCostumeSchema"]["properties"];
        for field in ["character_name", "description", "source_quote"] {
            assert!(
                costume[field].is_object(),
                "DraftCostumeSchema must expose `{field}`: {costume:?}"
            );
            assert!(
                costume[field]["description"].is_string(),
                "`{field}` needs a description, the schema is the model's contract"
            );
        }
        let required = defs(&value)["DraftSceneSchema"]["required"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect::<Vec<_>>();
        assert!(
            required.contains(&"costumes"),
            "`strict` schema mode requires every property: {required:?}"
        );
    }
}
