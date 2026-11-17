// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! One retry core for the provider-HTTP call sites (issue #925).
//!
//! Before this module five provider call sites answered the same three
//! questions independently — how an HTTP status is classified, how long to wait
//! between two attempts, and what the server said about the wait — and the
//! answers differed (base 500 ms doubling vs one fixed 250 ms pause vs no pause
//! at all; equal jitter vs full jitter; and nobody read a single header). This
//! module is the one place those answers live:
//!
//! * [`RetryClass`] — the status classification (`429`/5xx retryable, other 4xx
//!   rejected, everything else unexpected). The `DomainError` mapping stays at
//!   the call boundary ([`crate::ai::client::classify_http_status_with_detail`]),
//!   so the taxonomy is unchanged: the core returns data, never an error.
//! * [`RetryHint`] + [`parse_retry_hint`] — the server's own hint
//!   (`Retry-After`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`) as owned,
//!   `Copy`-friendly data. **Nothing acts on the hint yet**: issue #925 is the
//!   pure consolidation, and honouring `Retry-After` / distinguishing quota
//!   `429`s are deliberate follow-ups that then only touch the scheduling, not
//!   the call sites.
//! * [`Backoff`] — the wait strategies the call sites actually use, so each site
//!   states its policy in one vocabulary instead of re-approximating a formula.
//!
//! Design constraints (binding, issue #925): the core is **pure and stateless**
//! — no `Arc<T>`, no shared state, no async, no IO. Everything is a small value
//! in and a small value out, so it can be called from a projector supervisor, a
//! photo saga and a provider adapter without coupling them to each other. The
//! one exception is `tracing`: a malformed header is `None` + `tracing::debug!`,
//! never a validation error — a header we cannot read must not fail a request
//! that otherwise succeeded.

use std::time::{Duration, SystemTime};

use reqwest::StatusCode;
use reqwest::header::HeaderMap;

/// Base delay of the exponential backoff strategy: 500 ms, i.e. attempt `n`
/// waits `500 ms · 2^n` (plus jitter) before its retry.
///
/// One value for every exponential site; `projectors::supervisor` re-exports its
/// millisecond view as [`crate::projectors::supervisor::BACKOFF_BASE_MS`] and a
/// const assertion keeps the two from drifting apart.
pub(crate) const BACKOFF_BASE: Duration = Duration::from_millis(500);

/// Upper bound applied to any wait a server asks for.
///
/// A provider is a remote party: `Retry-After: 86400` is a day of holding a
/// concurrency permit, and a nonsense value must not be able to order an
/// unbounded pause. One day is comfortably above every real rate-limit window
/// we have seen (EURouter's free tier resets within a minute, Gemini's daily
/// quota within a day) and finite.
pub(crate) const MAX_SERVER_HINT: Duration = Duration::from_secs(86_400);

/// `X-RateLimit-Reset` values at or above this are read as epoch seconds,
/// smaller ones as "seconds from now".
///
/// The header has two shapes in the wild and no discriminator: a delta (the
/// common one, always far below 2^30) and a Unix timestamp (≈ 1.8 · 10^9 today,
/// and never below 10^9 again). 1_000_000_000 s = 2001-09-09, so the split is
/// unambiguous for every value either shape can produce after that date.
const EPOCH_RESET_THRESHOLD_SECS: u64 = 1_000_000_000;

/// Highest attempt index the exponential strategies distinguish.
///
/// `base · 2^n` is capped at `max` long before this, so clamping the exponent
/// changes no delay; it keeps the multiplication finite (a `u64` shift by ≥ 64
/// saturates, and `base · u64::MAX` would overflow).
const MAX_BACKOFF_EXPONENT: usize = 16;

/// How a provider's HTTP status is classified for retry purposes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum RetryClass {
    /// Worth another attempt: `429 Too Many Requests` and every `5xx`.
    ///
    /// A `429` is deliberately in here: today every site retries it, and
    /// separating quota exhaustion from a transient burst is a follow-up.
    Retryable,
    /// The provider refused this request; repeating it unchanged cannot help.
    Rejected,
    /// Neither a success nor one of the above: 1xx/3xx, or a non-standard code.
    Unexpected,
}

impl RetryClass {
    /// Classify one (non-success) HTTP status.
    #[must_use]
    pub(crate) fn of(status: StatusCode) -> Self {
        if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
            Self::Retryable
        } else if status.is_client_error() {
            Self::Rejected
        } else {
            Self::Unexpected
        }
    }
}

/// What one provider response says about retrying it.
///
/// Owned, `Copy` and free of lifetimes on purpose: [`reqwest::Response`] is
/// moved by `.text()`/`.json()`, so a hint borrowed from the response would be
/// unusable exactly where it is needed. Call sites therefore read the hint from
/// the headers **before** consuming the body.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct RetryHint {
    /// The status classification of the response that produced this hint.
    pub(crate) class: RetryClass,
    /// `Retry-After`, as "how long to wait from now".
    ///
    /// Both RFC 9110 forms are accepted: delta-seconds and an HTTP-date (all
    /// three date shapes — IMF-fixdate, RFC 850, asctime — via `httpdate`). A
    /// date in the past yields [`Duration::ZERO`]; an unparsable value yields
    /// `None`.
    pub(crate) wait: Option<Duration>,
    /// `X-RateLimit-Remaining`: how many requests the window still allows.
    pub(crate) limit_remaining: Option<u64>,
    /// `X-RateLimit-Reset`, normalised to "how long until the window resets",
    /// whichever of the two shapes the provider sent.
    pub(crate) limit_reset: Option<Duration>,
}

impl RetryHint {
    /// Whether the response carried any server-side hint at all.
    #[must_use]
    pub(crate) fn carries_server_hint(&self) -> bool {
        self.wait.is_some() || self.limit_remaining.is_some() || self.limit_reset.is_some()
    }
}

/// Read the server's retry hint out of a response's headers.
///
/// Takes the headers plus the status instead of a [`reqwest::Response`],
/// because the response is consumed by the body read that follows: borrowing
/// both keeps the call site able to read the hint before `.json()`/`.text()`.
///
/// Never fails. A missing header is `None`; a header we cannot read (non-ASCII
/// bytes, an unparsable number or date) is `None` plus a `tracing::debug!`, and
/// an absurd value is capped at [`MAX_SERVER_HINT`]. A bad header is the
/// provider's fault and must never turn a request that otherwise succeeded into
/// an error.
#[must_use]
pub(crate) fn parse_retry_hint(headers: &HeaderMap, status: StatusCode) -> RetryHint {
    parse_retry_hint_at(headers, status, SystemTime::now())
}

/// [`parse_retry_hint`] against an explicit clock.
///
/// Production reads `SystemTime::now()` exactly once per response; the tests pin
/// one timestamp instead. Keeping the clock a **parameter** is what makes the
/// parsers pure functions of `(headers, status, now)`: a relative header can be
/// asserted as an exact duration instead of a window that widens with the test's
/// own runtime (AGENTS.md §4 — no wall-clock budgets).
#[must_use]
fn parse_retry_hint_at(headers: &HeaderMap, status: StatusCode, now: SystemTime) -> RetryHint {
    RetryHint {
        class: RetryClass::of(status),
        wait: header_str(headers, "retry-after").and_then(|raw| parse_retry_after(raw, now)),
        limit_remaining: header_str(headers, "x-ratelimit-remaining")
            .and_then(parse_limit_remaining),
        limit_reset: header_str(headers, "x-ratelimit-reset")
            .and_then(|raw| parse_limit_reset(raw, now)),
    }
}

/// Log a hint at `debug` level when the response carried one.
///
/// The hint is not acted on yet (issue #925), but it is *read* at every call
/// site — which is the whole point: the follow-up that honours `Retry-After`
/// changes the scheduling decision, not the plumbing. Until then this line is
/// how the parser is validated against real provider traffic, and how a
/// malformed header becomes visible without becoming an error.
pub(crate) fn log_hint(site: &'static str, hint: &RetryHint) {
    if !hint.carries_server_hint() {
        return;
    }
    tracing::debug!(
        site,
        class = ?hint.class,
        wait_secs = hint.wait.map(|wait| wait.as_secs()),
        limit_remaining = hint.limit_remaining,
        limit_reset_secs = hint.limit_reset.map(|reset| reset.as_secs()),
        "provider response carried a retry hint (not acted on yet, issue #925)"
    );
}

/// The wait strategy of one retry loop.
///
/// Each call site states its policy once as a `const` and asks it for the delay
/// of one attempt, so the formula has one implementation while every site keeps
/// the timing it had before issue #925.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Backoff {
    /// The same pause on every attempt.
    Fixed(Duration),
    /// `base · 2^attempt` capped at `max`, plus up to 25 % jitter, capped again
    /// at `max`.
    EqualJitter { base: Duration, max: Duration },
    /// `base · 2^attempt` capped at `max`, then one uniform draw from
    /// `[0, capped]` ("full jitter").
    FullJitter { base: Duration, max: Duration },
}

impl Backoff {
    /// The delay before retry number `attempt` (0-indexed).
    #[must_use]
    pub(crate) fn delay(self, attempt: usize) -> Duration {
        match self {
            Self::Fixed(delay) => delay,
            Self::EqualJitter { base, max } => equal_jitter_delay(attempt, base, max),
            Self::FullJitter { base, max } => full_jitter_delay(attempt, base, max),
        }
    }
}

/// `base · 2^attempt` (capped at `max`), plus up to a quarter of that as
/// jitter, capped at `max` again.
fn equal_jitter_delay(attempt: usize, base: Duration, max: Duration) -> Duration {
    let ceiling = millis(max);
    let planned = millis(base)
        .saturating_mul(2_u64.saturating_pow(exponent(attempt)))
        .min(ceiling);
    let jitter = fastrand::u64(0..=planned / 4);
    Duration::from_millis(planned.saturating_add(jitter).min(ceiling))
}

/// `base · 2^attempt` (capped at `max`), then one uniform draw from
/// `[0, capped]`.
fn full_jitter_delay(attempt: usize, base: Duration, max: Duration) -> Duration {
    let ceiling = base
        .checked_mul(2_u32.saturating_pow(exponent(attempt)))
        .unwrap_or(max)
        .min(max);
    let nanos = u64::try_from(ceiling.as_nanos().max(1)).unwrap_or(u64::MAX);
    Duration::from_nanos(fastrand::u64(0..=nanos))
}

/// The bounded exponent of [`equal_jitter_delay`]/[`full_jitter_delay`].
fn exponent(attempt: usize) -> u32 {
    u32::try_from(attempt.min(MAX_BACKOFF_EXPONENT)).unwrap_or(MAX_BACKOFF_EXPONENT as u32)
}

/// Whole milliseconds of `duration`, saturating at `u64::MAX` instead of
/// truncating a century-long duration into a small number.
fn millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}

/// Cap a server-asked wait at [`MAX_SERVER_HINT`].
fn cap_server_hint(wait: Duration) -> Duration {
    wait.min(MAX_SERVER_HINT)
}

/// Read one header as text; an unreadable value is `None` plus a debug line.
fn header_str<'a>(headers: &'a HeaderMap, name: &'static str) -> Option<&'a str> {
    let value = headers.get(name)?;
    match value.to_str() {
        Ok(text) => Some(text),
        Err(error) => {
            // Obs-text bytes are legal in a header value but not UTF-8, so this
            // is reachable; it is still never a reason to fail the request.
            tracing::debug!(
                header = name,
                %error,
                "ignoring unreadable provider response header (issue #925)"
            );
            None
        }
    }
}

/// `Retry-After` as a wait: delta-seconds or an HTTP-date resolved against `now`.
#[must_use]
fn parse_retry_after(raw: &str, now: SystemTime) -> Option<Duration> {
    let raw = raw.trim();
    if raw.is_empty() {
        return None;
    }
    if let Ok(seconds) = raw.parse::<u64>() {
        return Some(cap_server_hint(Duration::from_secs(seconds)));
    }
    match httpdate::parse_http_date(raw) {
        // A date in the past means "you may retry now", not "wait -3 s".
        Ok(at) => Some(cap_server_hint(at.duration_since(now).unwrap_or_default())),
        Err(error) => {
            tracing::debug!(
                header = "retry-after",
                value = raw,
                %error,
                "unparsable provider hint; ignoring it (issue #925)"
            );
            None
        }
    }
}

/// `X-RateLimit-Remaining` as a counter.
#[must_use]
fn parse_limit_remaining(raw: &str) -> Option<u64> {
    let raw = raw.trim();
    match raw.parse::<u64>() {
        Ok(remaining) => Some(remaining),
        Err(error) => {
            tracing::debug!(
                header = "x-ratelimit-remaining",
                value = raw,
                %error,
                "unparsable provider hint; ignoring it (issue #925)"
            );
            None
        }
    }
}

/// `X-RateLimit-Reset` as "how long until the window resets", against `now`.
#[must_use]
fn parse_limit_reset(raw: &str, now: SystemTime) -> Option<Duration> {
    let raw = raw.trim();
    let Ok(value) = raw.parse::<u64>() else {
        tracing::debug!(
            header = "x-ratelimit-reset",
            value = raw,
            "unparsable provider hint; ignoring it (issue #925)"
        );
        return None;
    };
    let until_reset = if value >= EPOCH_RESET_THRESHOLD_SECS {
        SystemTime::UNIX_EPOCH
            .checked_add(Duration::from_secs(value))
            // A timestamp so far away that it overflows the clock is nonsense;
            // the cap is the answer, not an error.
            .map_or(MAX_SERVER_HINT, |at| {
                at.duration_since(now).unwrap_or_default()
            })
    } else {
        Duration::from_secs(value)
    };
    Some(cap_server_hint(until_reset))
}

#[cfg(test)]
#[path = "retry_tests.rs"]
mod retry_tests;
