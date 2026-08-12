// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

//! Server-side `detail` localization (ADR-031 D5).
//!
//! The problem builder renders the localized message for the negotiated
//! locale from the embedded Fluent bundles (`crates/api/locales/<lang>/errors.ftl`).
//! Negotiation parses `Accept-Language` q-values, matches against the
//! supported set, and falls back through the chain `requested* → de → en`;
//! an absent or garbage header defaults to `de`.
//!
//! Locale threading: the language middleware negotiates once per request and
//! stores the result in a [`tokio::task_local!`], which follows the request
//! task across `.await` points and worker threads — so the `IntoResponse`
//! conversion (which runs without access to request parts) can still resolve
//! the negotiated locale.

use fluent_bundle::{FluentArgs, FluentBundle, FluentResource};
use std::sync::{Arc, OnceLock};
use tokio::task_local;
use unic_langid::{LanguageIdentifier, langid};

use crate::problems::ProblemDetails;

/// Default locale: German (the product's primary language).
pub const DEFAULT_LOCALE: LanguageIdentifier = langid!("de");

/// The currently supported set. Adding a locale = adding
/// `locales/<lang>/errors.ftl` + one entry here (tree-only change, ADR-031
/// D5); the fallback chain is `requested* → de → en`.
pub const SUPPORTED_LOCALES: &[LanguageIdentifier] = &[langid!("de"), langid!("en")];

task_local! {
    static NEGOTIATED_LOCALE: LanguageIdentifier;
}

/// Parse the `Accept-Language` header (q-value aware) and negotiate against
/// the supported set; falls back through the chain to `de`.
///
/// - absent / garbage header → `de`;
/// - `uk, en;q=0.2, de;q=0.9` with `uk` unsupported → `de` (q=0.9 wins over
///   en at 0.2);
/// - `en` → `en`.
pub fn negotiate(header: Option<&str>) -> LanguageIdentifier {
    let Some(header) = header else {
        return DEFAULT_LOCALE;
    };
    for candidate in accept_language::parse(header) {
        let Ok(requested) = candidate.parse::<LanguageIdentifier>() else {
            continue;
        };
        // `matches` treats the more specific side as the range; `en-US`
        // requested with only `en` supported still matches `en`.
        if let Some(supported) = SUPPORTED_LOCALES
            .iter()
            .find(|s| s.matches(&requested, true, true))
        {
            return supported.clone();
        }
    }
    DEFAULT_LOCALE
}

/// The locale negotiated for the current request (task-scoped); `de` when
/// no negotiation ran (tests, fallback paths).
pub fn current_locale() -> LanguageIdentifier {
    NEGOTIATED_LOCALE
        .try_with(|locale| locale.clone())
        .unwrap_or(DEFAULT_LOCALE)
}

/// The `Accept-Language` negotiation middleware: stores the negotiated
/// locale in the request's task scope so the problem builder can localize
/// `detail` during response conversion. Outermost in the api stack, so auth
/// rejections are localized too.
pub async fn negotiate_language(
    req: axum::http::Request<axum::body::Body>,
    next: axum::middleware::Next,
) -> axum::response::Response {
    let header = req
        .headers()
        .get(axum::http::header::ACCEPT_LANGUAGE)
        .and_then(|value| value.to_str().ok());
    let locale = negotiate(header);
    NEGOTIATED_LOCALE.scope(locale, next.run(req)).await
}

// ---------------------------------------------------------------------------
// Fluent bundles
//
// `FluentBundle` is not `Send + Sync` (its intl memoizer uses `RefCell`), so
// bundles are built per call. The FTL files are small (~10 KB) and this only
// runs on error paths (a problem is being rendered); the coverage lint keeps
// the files parseable in CI. A Send-safe bundle cache is a follow-up if the
// error rate ever justifies it.
// ---------------------------------------------------------------------------

fn bundle_source(locale: &LanguageIdentifier) -> &'static str {
    if locale == &langid!("en") {
        include_str!("../../locales/en/errors.ftl")
    } else {
        include_str!("../../locales/de/errors.ftl")
    }
}

/// Cached parse of each embedded bundle. `FluentResource` is `Send + Sync`,
/// so the (expensive) FTL parse happens once per locale; only the small
/// `FluentBundle` is built per call. Error paths (auth floods, route
/// scanning) therefore stop re-parsing the whole FTL on every problem.
fn parsed_resource(locale: &LanguageIdentifier) -> &'static Arc<FluentResource> {
    static DE: OnceLock<Arc<FluentResource>> = OnceLock::new();
    static EN: OnceLock<Arc<FluentResource>> = OnceLock::new();
    let (cell, source) = if locale == &langid!("en") {
        (&EN, bundle_source(locale))
    } else {
        (&DE, bundle_source(locale))
    };
    cell.get_or_init(|| {
        Arc::new(match FluentResource::try_new(source.to_owned()) {
            Ok(resource) => resource,
            Err((resource, errors)) => {
                // The coverage lint validates parseability in CI; production
                // degrades to the title fallback, never panics (AGENTS.md §3).
                tracing::error!(
                    ?errors,
                    "malformed Fluent bundle; detail falls back to title"
                );
                resource
            }
        })
    })
}

/// Render the localized `detail` for a problem code with the declared
/// extension values as Fluent arguments (ADR-031 D5: interpolation only,
/// never string building). Returns `None` when the locale has no message
/// for the code (the builder then falls back to the constant English title).
pub fn localize(locale: &LanguageIdentifier, code: &str, args: &FluentArgs) -> Option<String> {
    let resource = Arc::clone(parsed_resource(locale));
    let mut bundle = FluentBundle::new(vec![locale.clone()]);
    if let Err(errors) = bundle.add_resource(resource) {
        tracing::error!(
            ?errors,
            "failed to add Fluent resource; detail falls back to title"
        );
        return None;
    }
    let key = format!("problem-{}", code.replace('.', "-"));
    let message = bundle.get_message(&key)?;
    let pattern = message.value()?;
    let mut errors = Vec::new();
    let value = bundle.format_pattern(pattern, Some(args), &mut errors);
    if !errors.is_empty() {
        tracing::warn!(?errors, code, "Fluent message resolution errors");
    }
    Some(value.into_owned())
}

/// Populate Fluent args from the problem's declared extension values (only
/// S0/S1 fields reach the message — the builder already whitelisted them).
pub fn fluent_args<'a>(document: &'a ProblemDetails) -> FluentArgs<'a> {
    let mut args = FluentArgs::new();
    if let Some(extensions) = &document.extensions {
        for (name, value) in extensions {
            match value {
                serde_json::Value::String(s) => {
                    args.set(name.as_str(), fluent_bundle::FluentValue::from(s.as_str()))
                }
                serde_json::Value::Number(n) => {
                    if let Some(i) = n.as_i64() {
                        args.set(name.as_str(), i);
                    } else if let Some(f) = n.as_f64() {
                        args.set(name.as_str(), f);
                    }
                }
                // No registered extension is a boolean; skip other shapes.
                _ => {}
            }
        }
    }
    args
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn negotiate_absent_header_defaults_to_german() {
        assert_eq!(negotiate(None), langid!("de"));
        assert_eq!(negotiate(Some("")), langid!("de"));
        assert_eq!(negotiate(Some("!!!garbage!!!")), langid!("de"));
    }

    #[test]
    fn negotiate_q_values_are_honoured() {
        // `uk` unsupported → `de` wins over `en` (q=0.9 vs 0.2).
        assert_eq!(negotiate(Some("uk, en;q=0.2, de;q=0.9")), langid!("de"));
        // en with higher q wins over de.
        assert_eq!(negotiate(Some("de;q=0.5, en;q=0.8")), langid!("en"));
        // Unsupported-only header falls through to de.
        assert_eq!(negotiate(Some("fr, uk;q=0.9")), langid!("de"));
    }

    #[test]
    fn negotiate_supported_locale_returns_itself() {
        assert_eq!(negotiate(Some("en")), langid!("en"));
        assert_eq!(negotiate(Some("de")), langid!("de"));
        // Region-tagged request matches the language tag (range matching).
        assert_eq!(negotiate(Some("de-DE")), langid!("de"));
    }

    #[test]
    fn current_locale_defaults_to_german_outside_request() {
        assert_eq!(current_locale(), langid!("de"));
    }
}
