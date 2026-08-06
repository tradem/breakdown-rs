// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4-flash (opencode-go)

//! Explicit redirect & transport policy for AI provider HTTP clients
//! (issue #170).
//!
//! The AI adapters previously relied on reqwest stripping the
//! `Authorization` header on cross-host redirects. That implicit behavior is
//! **not** the application transport policy, and it has a gap: reqwest only
//! strips sensitive headers when the redirect changes host *or port* — a
//! same-host HTTPS→HTTP downgrade keeps the bearer token. This module defines
//! and enforces the policy explicitly, at the HTTP-client configuration site.
//!
//! ## Policy
//!
//! Two regimes apply, decided from the **original** request URL:
//!
//! * **Hosted providers** (OpenAI, OpenRouter, EURouter, Neuralwatt,
//!   OpenCodeGo, OpenCode — every curated provider whose base URL is HTTPS):
//!   a redirect hop is followed only when its destination
//!   1. is `https://` (this rejects HTTPS→HTTP downgrades, including
//!      same-host ones where reqwest would otherwise forward credentials), and
//!   2. has the same host **and port** as the original request — the curated
//!      base URL is the only approved destination, so cross-host redirects are
//!      rejected outright.
//!
//!   Vaulted bearer credentials therefore never leave the approved origin
//!   (CWE-522 / CWE-601).
//!
//! * **Ollama** (local-only): the endpoint is a local Docker-internal service
//!   (`http://ollama:11434/api`) and carries no credentials, but the request
//!   body contains untrusted source-document text. A redirect hop is followed
//!   only when its destination is a *local* destination: the original host,
//!   the `localhost` names, or an IP literal in loopback, private
//!   (RFC 1918), link-local (RFC 3927) or unique-local (RFC 4193) address
//!   space. Redirects to public internet destinations are rejected so the
//!   script source text is never exfiltrated.
//!
//! Both regimes additionally bound the redirect chain to
//! [`MAX_REDIRECT_HOPS`] hops — `reqwest::redirect::Policy::custom` does not
//! apply the default 10-hop limit itself.
//!
//! Unit and end-to-end tests for every allowed/rejected case live in the
//! `#[cfg(test)] mod tests` at the bottom of this file.

use std::error::Error;
use std::fmt;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::time::Duration;

use reqwest::Url;
use reqwest::redirect::{Action, Attempt, Policy};
use url::Host;

use super::CuratedProviderUrls;
use breakdown_core::ai::{CuratedLlmProvider, LlmProvider};

/// Maximum redirect hops followed per request. `Policy::custom` replaces
/// reqwest's default policy entirely, so the hop bound is enforced here.
pub const MAX_REDIRECT_HOPS: usize = 5;

/// A redirect hop that was rejected by the transport policy.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RedirectViolation {
    /// Hosted provider: the destination is not `https://` (blocks HTTPS→HTTP
    /// downgrade redirects, which reqwest would otherwise follow while keeping
    /// the `Authorization` header on the same host).
    NonHttps { destination: String },
    /// Hosted provider: the destination host/port differs from the original
    /// request, i.e. it is outside the approved curated origin.
    CrossHost {
        destination: String,
        original: String,
    },
    /// Ollama: the destination is not a local address/host, so following it
    /// would exfiltrate the source-document text to a public destination.
    NonLocalDestination { destination: String },
    /// Hosted: the destination hostname could not be resolved, so it cannot
    /// be vetted against the public-only policy — fail closed.
    DnsLookupFailed { host: String },
    /// Hosted: the destination hostname resolves to an internal address
    /// (private, loopback, link-local, unique-local, …) even though the
    /// hostname and scheme are otherwise allowed — DNS-rebinding guard.
    InternalDestination { host: String, resolved: String },
    /// The reqwest client could not be built for the hosted regime.
    ClientBuildFailed { error: String },
    /// The redirect chain exceeded [`MAX_REDIRECT_HOPS`] hops.
    TooManyRedirects { hops: usize },
    /// No original URL was recorded (defensive; reqwest always supplies the
    /// initial request URL as the first entry of `previous()`).
    MissingOriginalUrl,
}

impl fmt::Display for RedirectViolation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RedirectViolation::NonHttps { destination } => write!(
                f,
                "hosted provider redirect to non-HTTPS destination {destination} \
                 rejected by transport policy (HTTPS-only)"
            ),
            RedirectViolation::CrossHost {
                destination,
                original,
            } => write!(
                f,
                "hosted provider redirect from {original} to {destination} rejected \
                 by transport policy (redirects must stay on the approved origin)"
            ),
            RedirectViolation::NonLocalDestination { destination } => write!(
                f,
                "Ollama redirect to non-local destination {destination} rejected \
                 by transport policy (local-only)"
            ),
            RedirectViolation::DnsLookupFailed { host } => write!(
                f,
                "hosted provider destination {host} could not be resolved; \
                 refusing to connect (public-only transport policy)"
            ),
            RedirectViolation::InternalDestination { host, resolved } => write!(
                f,
                "hosted provider destination {host} resolves to internal \
                 address(es) {resolved} and is rejected by transport policy \
                 (public-only: private, loopback and other internal address \
                 space is never contacted)"
            ),
            RedirectViolation::ClientBuildFailed { error } => {
                write!(f, "hosted provider HTTP client could not be built: {error}")
            }
            RedirectViolation::TooManyRedirects { hops } => write!(
                f,
                "redirect chain exceeded {MAX_REDIRECT_HOPS} hops ({hops} URLs visited)"
            ),
            RedirectViolation::MissingOriginalUrl => write!(
                f,
                "redirect encountered without an original request URL; refusing to follow"
            ),
        }
    }
}

impl Error for RedirectViolation {}

/// Hosted-provider redirect decision (issue #170): the destination must be
/// HTTPS and stay on the original request's host *and port*. Everything else
/// is rejected before any connection is attempted, so credentials are never
/// forwarded to an unapproved destination.
///
/// The address dimension of this check is enforced at request time by
/// [`validate_public_resolution`] / [`build_hosted_client`]: the origin
/// hostname is resolved, every resolved address must be globally routable
/// (private/loopback/internal is rejected even when the hostname and scheme
/// are allowed), and the validated addresses are pinned for the whole request
/// chain. Because this policy rejects cross-host redirects, every redirect
/// target is covered by the same pin (DNS-rebinding guard).
pub fn hosted_redirect_allowed(next: &Url, original: &Url) -> Result<(), RedirectViolation> {
    if next.scheme() != "https" {
        return Err(RedirectViolation::NonHttps {
            destination: next.to_string(),
        });
    }
    let same_origin = next.host_str() == original.host_str()
        && next.port_or_known_default() == original.port_or_known_default();
    if !same_origin {
        return Err(RedirectViolation::CrossHost {
            destination: next.to_string(),
            original: original.to_string(),
        });
    }
    Ok(())
}

/// Ollama redirect decision (issue #170): the destination must be a local
/// endpoint — the original host, the `localhost` names, or an IP literal in
/// loopback / private / link-local / unique-local address space.
pub fn ollama_redirect_allowed(next: &Url, original: &Url) -> Result<(), RedirectViolation> {
    if is_local_destination(next, original) {
        Ok(())
    } else {
        Err(RedirectViolation::NonLocalDestination {
            destination: next.to_string(),
        })
    }
}

/// True when `url` points at a local endpoint. The host match is deliberately
/// port-agnostic: the Ollama regime protects against leaving the local
/// network, not against a port change inside it (the hosted regime compares
/// host and port).
fn is_local_destination(url: &Url, original: &Url) -> bool {
    if url.host().is_some() && url.host() == original.host() {
        return true;
    }
    match url.host() {
        Some(Host::Domain(domain)) => is_local_domain(domain),
        Some(Host::Ipv4(address)) => is_local_ipv4(address),
        Some(Host::Ipv6(address)) => is_local_ipv6(address),
        // A URL without a host is never a valid HTTP destination.
        None => false,
    }
}

/// The `localhost` names. The url crate normalizes domains to lowercase
/// punycode, so plain comparison is sufficient.
fn is_local_domain(domain: &str) -> bool {
    matches!(domain, "localhost" | "localhost.localdomain")
}

/// Loopback, RFC 1918 private, RFC 3927 link-local, RFC 6598 shared
/// (CGNAT) address space and the unspecified address. These cover localhost,
/// LANs and Docker/Kubernetes pod networks — the realistic deployment
/// topologies for a local Ollama endpoint. Documentation (TEST-NET) and
/// multicast ranges plus the broadcast address are also not globally
/// routable, so they count as local for the transport policies.
fn is_local_ipv4(address: Ipv4Addr) -> bool {
    address.is_loopback()
        || address.is_private()
        || address.is_link_local()
        || address.is_unspecified()
        || address.is_multicast()
        || address.is_documentation()
        || address == Ipv4Addr::BROADCAST
        || is_rfc6598_shared(address)
}

/// RFC 6598 shared address space (`100.64.0.0/10`), used by CGNAT. It is not
/// globally routable, and `Ipv4Addr::is_private()` deliberately excludes it,
/// so the range is checked explicitly here.
fn is_rfc6598_shared(address: Ipv4Addr) -> bool {
    let octets = address.octets();
    octets[0] == 100 && (octets[1] & 0b1100_0000) == 0b0100_0000
}

/// Loopback, unique-local (RFC 4193), unicast link-local (RFC 4291), the
/// unspecified address and IPv4-mapped forms of [`is_local_ipv4`] (e.g.
/// `::ffff:127.0.0.1`). Multicast and the RFC 3849 documentation prefix
/// (`2001:db8::/32`, matched manually because `Ipv6Addr::is_documentation`
/// is unstable) are not globally routable either, so they count as local.
fn is_local_ipv6(address: Ipv6Addr) -> bool {
    address.is_loopback()
        || address.is_unique_local()
        || address.is_unicast_link_local()
        || address.is_unspecified()
        || address.is_multicast()
        || is_documentation_ipv6(address)
        || address.to_ipv4_mapped().is_some_and(is_local_ipv4)
}

/// RFC 3849 documentation prefix (`2001:db8::/32`) — not globally routable.
fn is_documentation_ipv6(address: Ipv6Addr) -> bool {
    address.segments()[0] == 0x2001 && address.segments()[1] == 0x0db8
}

/// True when `ip` is a globally routable address — the complement of the
/// local/private/loopback classification used by the transport policies.
fn is_public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(address) => !is_local_ipv4(address),
        IpAddr::V6(address) => !is_local_ipv6(address),
    }
}

/// Resolve `host` and fail closed unless **every** resolved address is
/// globally routable (DNS-rebinding guard for the hosted regime, issue #170):
/// an allowlisted hostname may still resolve to a private or loopback
/// address — e.g. via an attacker-controlled DNS answer or a hosts override
/// — and connecting there would deliver bearer credentials to an internal
/// service. Returns the validated addresses so the caller can pin them via
/// `ClientBuilder::resolve_to_addrs`.
pub async fn validate_public_resolution(host: &str) -> Result<Vec<SocketAddr>, RedirectViolation> {
    let addrs: Vec<SocketAddr> = tokio::net::lookup_host((host, 0))
        .await
        .map_err(|_error| RedirectViolation::DnsLookupFailed {
            host: host.to_owned(),
        })?
        .collect();
    if addrs.is_empty() {
        return Err(RedirectViolation::DnsLookupFailed {
            host: host.to_owned(),
        });
    }
    let internal: Vec<String> = addrs
        .iter()
        .filter(|addr| !is_public_ip(addr.ip()))
        .map(|addr| addr.ip().to_string())
        .collect();
    if !internal.is_empty() {
        return Err(RedirectViolation::InternalDestination {
            host: host.to_owned(),
            resolved: internal.join(", "),
        });
    }
    Ok(addrs)
}

/// Build the hosted-regime HTTP client for `host`: validates the resolution
/// ([`validate_public_resolution`]), pins the vetted addresses with
/// `ClientBuilder::resolve_to_addrs`, applies the HTTPS-only same-origin
/// redirect policy ([`hosted_provider_redirect_policy`]) and the request
/// deadline. The pin covers the initial request and every redirect target:
/// the policy rejects cross-host hops, so the whole chain stays on the
/// validated host and cannot be rebound after validation.
pub async fn build_hosted_client(
    host: &str,
    timeout: Duration,
) -> Result<reqwest::Client, RedirectViolation> {
    let addrs = validate_public_resolution(host).await?;
    reqwest::Client::builder()
        .timeout(timeout)
        .redirect(hosted_provider_redirect_policy())
        .resolve_to_addrs(host, &addrs)
        .build()
        .map_err(|error| RedirectViolation::ClientBuildFailed {
            error: error.to_string(),
        })
}

/// Apply a decision function to a redirect attempt, enforcing the hop bound
/// first. Shared by all three policies.
fn apply_policy<F>(attempt: Attempt, decision: F) -> Action
where
    F: FnOnce(&Url, &Url) -> Result<(), RedirectViolation>,
{
    // `previous()` starts with the original request URL and grows by one per
    // followed hop; `len() > MAX_REDIRECT_HOPS` means this hop would be the
    // (MAX_REDIRECT_HOPS + 1)-th, mirroring reqwest's default limit semantics.
    let hops = attempt.previous().len();
    if hops > MAX_REDIRECT_HOPS {
        return attempt.error(RedirectViolation::TooManyRedirects { hops });
    }
    let Some(original) = attempt.previous().first() else {
        return attempt.error(RedirectViolation::MissingOriginalUrl);
    };
    match decision(attempt.url(), original) {
        Ok(()) => attempt.follow(),
        Err(violation) => attempt.error(violation),
    }
}

/// Redirect policy for the hosted-provider chat client: HTTPS-only,
/// same-origin redirects.
pub fn hosted_provider_redirect_policy() -> Policy {
    Policy::custom(|attempt| apply_policy(attempt, hosted_redirect_allowed))
}

/// Redirect policy for the local Ollama endpoint: local-only destinations.
pub fn ollama_redirect_policy() -> Policy {
    Policy::custom(|attempt| apply_policy(attempt, ollama_redirect_allowed))
}

/// Redirect policy for the curated model catalog, which serves both hosted and
/// Ollama providers from a single client. The regime is selected from the
/// original request URL: requests to the curated Ollama origin are local-only,
/// everything else follows the hosted policy.
pub fn curated_provider_redirect_policy() -> Policy {
    let ollama_host = ollama_origin_host();
    Policy::custom(move |attempt| {
        apply_policy(attempt, |next, original| {
            curated_redirect_allowed(next, original, ollama_host.as_deref())
        })
    })
}

/// Regime dispatch for the curated model catalog: an original request to the
/// curated Ollama origin is governed by the local-only policy, everything else
/// by the hosted (HTTPS-only, same-origin) policy. `ollama_host` is the
/// parsed host of the curated Ollama base URL; `None` degrades to hosted.
pub fn curated_redirect_allowed(
    next: &Url,
    original: &Url,
    ollama_host: Option<&str>,
) -> Result<(), RedirectViolation> {
    if original.host_str() == ollama_host {
        ollama_redirect_allowed(next, original)
    } else {
        hosted_redirect_allowed(next, original)
    }
}

/// Host of the curated Ollama base URL, best-effort. The constant is a static
/// literal under our control; `None` degrades the catalog policy to the
/// hosted regime (which is the safe default: HTTPS-only).
fn ollama_origin_host() -> Option<String> {
    let base = CuratedProviderUrls::base_url(LlmProvider::Ollama);
    Url::parse(base)
        .ok()
        .and_then(|url| url.host_str().map(str::to_owned))
}

#[cfg(test)]
mod tests {
    // Test code lifts the workspace clippy panics/unwrap lints via
    // `#![cfg_attr(test, allow(...))]` in `crates/infra/src/lib.rs`.

    use std::error::Error;
    use std::io::{Read, Write};
    use std::net::SocketAddr;
    use std::time::Duration;

    use reqwest::Url;

    use super::*;

    fn url(value: &str) -> Url {
        Url::parse(value).unwrap_or_else(|error| panic!("invalid test URL {value}: {error}"))
    }

    fn hosted_original() -> Url {
        url("https://api.openai.com/v1/chat/completions")
    }

    fn ollama_original() -> Url {
        url("http://ollama:11434/api/chat")
    }

    /// Builds `http://<host>:11434/api/chat`, bracketing IPv6 literals.
    fn local_url(host: &str) -> Url {
        let host = if host.contains(':') {
            format!("[{host}]")
        } else {
            host.to_owned()
        };
        url(&format!("http://{host}:11434/api/chat"))
    }

    /// Flatten the reqwest error chain so policy messages (which live in the
    /// source chain behind "error following redirect") are assertable.
    fn policy_message(error: &reqwest::Error) -> String {
        let mut messages = vec![error.to_string()];
        let mut source = error.source();
        while let Some(cause) = source {
            messages.push(cause.to_string());
            source = cause.source();
        }
        messages.join(" | ")
    }

    // ── Hosted regime: pure decision ────────────────────────────────────────

    #[test]
    fn hosted_allows_same_origin_https_redirect() {
        let next = url("https://api.openai.com/v1/chat/completions/retry");
        assert_eq!(hosted_redirect_allowed(&next, &hosted_original()), Ok(()));
    }

    #[test]
    fn hosted_allows_same_origin_https_redirect_with_explicit_default_port() {
        let next = url("https://api.openai.com:443/v1/other");
        assert_eq!(hosted_redirect_allowed(&next, &hosted_original()), Ok(()));
    }

    #[test]
    fn hosted_rejects_https_to_http_downgrade_on_same_host() {
        // This is exactly the case reqwest would follow while *keeping* the
        // Authorization header (it only strips on host/port change) — the
        // explicit policy must reject it.
        let next = url("http://api.openai.com/v1/chat/completions");
        assert_eq!(
            hosted_redirect_allowed(&next, &hosted_original()),
            Err(RedirectViolation::NonHttps {
                destination: next.to_string(),
            })
        );
    }

    #[test]
    fn hosted_rejects_cross_host_https_redirect() {
        let next = url("https://cdn.openai.com/v1/models");
        assert_eq!(
            hosted_redirect_allowed(&next, &hosted_original()),
            Err(RedirectViolation::CrossHost {
                destination: next.to_string(),
                original: hosted_original().to_string(),
            })
        );
    }

    #[test]
    fn hosted_rejects_port_change_on_same_host() {
        let next = url("https://api.openai.com:8443/v1/other");
        assert_eq!(
            hosted_redirect_allowed(&next, &hosted_original()),
            Err(RedirectViolation::CrossHost {
                destination: next.to_string(),
                original: hosted_original().to_string(),
            })
        );
    }

    // ── Hosted regime: DNS-resolution guard (issue #170) ───────────────────

    #[tokio::test]
    async fn hosted_resolution_rejects_private_ipv4() {
        // Loopback, RFC 1918, link-local, CGNAT (RFC 6598) and the
        // unspecified address must all be rejected even though an allowlisted
        // *hostname* could resolve to any of them (DNS rebinding).
        for host in [
            "127.0.0.1",
            "10.0.0.5",
            "172.16.9.9",
            "192.168.1.10",
            "169.254.1.1",
            "100.64.0.1",
            "0.0.0.0",
        ] {
            let err = validate_public_resolution(host).await.unwrap_err();
            assert!(
                matches!(err, RedirectViolation::InternalDestination { .. }),
                "{host} must be rejected as an internal destination, got {err:?}"
            );
        }
    }

    #[tokio::test]
    async fn hosted_resolution_rejects_ipv6_loopback_and_unique_local() {
        for host in ["::1", "fd00::1", "fe80::1", "::ffff:127.0.0.1"] {
            let err = validate_public_resolution(host).await.unwrap_err();
            assert!(
                matches!(err, RedirectViolation::InternalDestination { .. }),
                "{host} must be rejected as an internal destination, got {err:?}"
            );
        }
    }

    #[tokio::test]
    async fn hosted_resolution_rejects_hostname_resolving_to_local() {
        // The DNS-rebinding class: the hostname text itself is "allowed",
        // but the system resolver maps it onto loopback (/etc/hosts).
        let err = validate_public_resolution("localhost").await.unwrap_err();
        assert!(
            matches!(err, RedirectViolation::InternalDestination { .. }),
            "localhost must be rejected via its resolved addresses, got {err:?}"
        );
    }

    #[tokio::test]
    async fn hosted_resolution_allows_public_ipv4() {
        // IP literals resolve to themselves without DNS, so this is
        // deterministic and network-free.
        let addrs = validate_public_resolution("8.8.8.8").await.unwrap();
        assert!(
            !addrs.is_empty() && addrs.iter().all(|addr| is_public_ip(addr.ip())),
            "8.8.8.8 must resolve to public addresses, got {addrs:?}"
        );
    }

    #[tokio::test]
    async fn hosted_resolution_rejects_unresolvable_host() {
        // RFC 2606 documents .invalid as never resolvable; the guard must
        // fail closed instead of connecting blind.
        let err = validate_public_resolution("transport-policy.invalid")
            .await
            .unwrap_err();
        assert!(
            matches!(err, RedirectViolation::DnsLookupFailed { .. }),
            "unresolvable host must fail closed, got {err:?}"
        );
    }

    #[tokio::test]
    async fn build_hosted_client_rejects_internal_destination() {
        let err = build_hosted_client("localhost", Duration::from_secs(1))
            .await
            .unwrap_err();
        assert!(
            matches!(err, RedirectViolation::InternalDestination { .. }),
            "localhost must never yield a hosted client, got {err:?}"
        );
    }

    #[tokio::test]
    async fn build_hosted_client_pins_and_validates_public_destination() {
        // A public IP literal yields a usable pinned client (deterministic,
        // no network access performed at build time).
        let client = build_hosted_client("8.8.8.8", Duration::from_secs(1))
            .await
            .unwrap();
        assert_eq!(
            client
                .get("https://8.8.8.8/health")
                .build()
                .unwrap()
                .url()
                .host_str(),
            Some("8.8.8.8")
        );
    }

    // ── Ollama regime: pure decision ────────────────────────────────────────

    #[test]
    fn ollama_allows_same_host_redirect() {
        let next = url("http://ollama:11434/api/v1/chat");
        assert_eq!(ollama_redirect_allowed(&next, &ollama_original()), Ok(()));
    }

    #[test]
    fn ollama_allows_loopback_redirect() {
        let next = url("http://127.0.0.1:11434/api/chat");
        assert_eq!(ollama_redirect_allowed(&next, &ollama_original()), Ok(()));
    }

    #[test]
    fn ollama_allows_ipv6_loopback_redirect() {
        let next = url("http://[::1]:11434/api/chat");
        assert_eq!(ollama_redirect_allowed(&next, &ollama_original()), Ok(()));
    }

    #[test]
    fn ollama_allows_ipv4_mapped_loopback_redirect() {
        let next = url("http://[::ffff:127.0.0.1]:11434/api/chat");
        assert_eq!(ollama_redirect_allowed(&next, &ollama_original()), Ok(()));
    }

    #[test]
    fn ollama_allows_private_network_redirect() {
        for host in [
            "10.0.0.5",
            "172.16.42.1",
            "172.31.255.254",
            "192.168.1.10",
            "192.168.0.0",
        ] {
            let next = url(&format!("http://{host}:11434/api/chat"));
            assert_eq!(
                ollama_redirect_allowed(&next, &ollama_original()),
                Ok(()),
                "expected {host} to be a local destination"
            );
        }
    }

    #[test]
    fn ollama_allows_link_local_unspecified_and_unique_local() {
        for host in ["169.254.1.1", "0.0.0.0", "fe80::1", "::", "fd00::1234"] {
            let next = local_url(host);
            assert_eq!(
                ollama_redirect_allowed(&next, &ollama_original()),
                Ok(()),
                "expected {host} to be a local destination"
            );
        }
    }

    #[test]
    fn ollama_allows_rfc6598_shared_address_space() {
        // RFC 6598 (100.64.0.0/10) first and last addresses plus interior
        // samples; `is_private()` does not cover this range.
        for host in [
            "100.64.0.0",
            "100.64.0.1",
            "100.127.255.254",
            "100.127.255.255",
        ] {
            let next = local_url(host);
            assert_eq!(
                ollama_redirect_allowed(&next, &ollama_original()),
                Ok(()),
                "expected {host} to be a local destination"
            );
        }
    }

    #[test]
    fn ollama_rejects_addresses_immediately_outside_rfc6598_shared_range() {
        // One below (100.63.255.255) and one above (100.128.0.0) the range.
        for host in ["100.63.255.255", "100.128.0.0", "100.128.0.1"] {
            let next = local_url(host);
            assert_eq!(
                ollama_redirect_allowed(&next, &ollama_original()),
                Err(RedirectViolation::NonLocalDestination {
                    destination: next.to_string(),
                }),
                "expected {host} to be rejected as non-local"
            );
        }
    }

    #[test]
    fn ollama_allows_localhost_name_redirect() {
        for next in [
            url("http://localhost:11434/api/chat"),
            url("http://localhost.localdomain:11434/api/chat"),
        ] {
            assert_eq!(ollama_redirect_allowed(&next, &ollama_original()), Ok(()));
        }
    }

    #[test]
    fn ollama_rejects_public_hostname_redirect() {
        let next = url("https://ollama.example.com/api/chat");
        assert_eq!(
            ollama_redirect_allowed(&next, &ollama_original()),
            Err(RedirectViolation::NonLocalDestination {
                destination: next.to_string(),
            })
        );
    }

    #[test]
    fn ollama_rejects_public_ip_redirect() {
        for host in [
            "8.8.8.8",
            "93.184.216.34",
            "2606:2800:220:1:248:1893:25c8:1946",
        ] {
            let next = local_url(host);
            assert_eq!(
                ollama_redirect_allowed(&next, &ollama_original()),
                Err(RedirectViolation::NonLocalDestination {
                    destination: next.to_string(),
                }),
                "expected {host} to be rejected as non-local"
            );
        }
    }

    // ── End-to-end: policies attached to real reqwest clients ───────────────

    /// Minimal HTTP/1.1 test server on a random loopback port:
    /// * `/redirect` → 307 to the configured `redirect_location`
    /// * `/hop/{n}`   → 307 to `/hop/{n+1}` (a redirect loop for hop-bound tests)
    /// * `/final`     → 200 with body `ok`
    /// * anything else → 404
    fn spawn_redirect_server(redirect_location: &str) -> SocketAddr {
        let listener = std::net::TcpListener::bind("127.0.0.1:0")
            .unwrap_or_else(|error| panic!("cannot bind test server: {error}"));
        let address = listener
            .local_addr()
            .unwrap_or_else(|error| panic!("cannot read test server address: {error}"));
        let redirect_location = redirect_location.to_owned();
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let redirect_location = redirect_location.clone();
                std::thread::spawn(move || {
                    let mut buffer = [0u8; 4096];
                    let Ok(read) = stream.read(&mut buffer) else {
                        return;
                    };
                    let request = String::from_utf8_lossy(&buffer[..read]).to_string();
                    let path = request.split_whitespace().nth(1).unwrap_or("/");
                    let response = match path {
                        "/redirect" => format!(
                            "HTTP/1.1 307 Temporary Redirect\r\nLocation: {redirect_location}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        ),
                        path if path.starts_with("/hop/") => {
                            let next = path["/hop/".len()..]
                                .parse::<u32>()
                                .map_or(1, |hop| hop + 1);
                            format!(
                                "HTTP/1.1 307 Temporary Redirect\r\nLocation: /hop/{next}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            )
                        }
                        "/final" => {
                            "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                                .to_owned()
                        }
                        _ => {
                            "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                                .to_owned()
                        }
                    };
                    // Test helper: the local test server discards write errors
                    // intentionally — the client-side assertion decides the
                    // outcome, there is no production retry machinery to feed.
                    // ast-grep-ignore: discard-result
                    let _ = stream.write_all(response.as_bytes());
                });
            }
        });
        address
    }

    fn client_with(policy: reqwest::redirect::Policy) -> reqwest::Client {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(10))
            .redirect(policy)
            .build()
            .unwrap_or_else(|error| panic!("cannot build test client: {error}"))
    }

    #[tokio::test]
    async fn ollama_policy_follows_local_loopback_redirect() {
        let address = spawn_redirect_server("/final");
        let base = format!("http://{address}");
        let client = client_with(ollama_redirect_policy());
        let response = client
            .get(format!("{base}/redirect"))
            .send()
            .await
            .unwrap_or_else(|error| panic!("request failed: {error}"));
        assert_eq!(response.status(), reqwest::StatusCode::OK);
        let body = response
            .text()
            .await
            .unwrap_or_else(|error| panic!("cannot read body: {error}"));
        assert_eq!(body, "ok");
    }

    #[tokio::test]
    async fn ollama_policy_rejects_redirect_to_public_host() {
        // The policy must reject before any connection to the public host is
        // attempted, so this test needs no network access.
        let address = spawn_redirect_server("http://8.8.8.8/evil");
        let base = format!("http://{address}");
        let client = client_with(ollama_redirect_policy());
        let error = client
            .get(format!("{base}/redirect"))
            .send()
            .await
            .expect_err("redirect to a public host must be rejected");
        assert!(
            error.is_redirect(),
            "expected a redirect-policy error: {error}"
        );
        let message = policy_message(&error);
        assert!(
            message.contains("non-local destination"),
            "unexpected error message: {message}"
        );
    }

    #[tokio::test]
    async fn hosted_policy_rejects_http_redirect_destination() {
        // A local HTTP redirect destination is a plain `http://` URL, which
        // the hosted policy must reject (HTTPS-only).
        let address = spawn_redirect_server("/final");
        let base = format!("http://{address}");
        let client = client_with(hosted_provider_redirect_policy());
        let error = client
            .get(format!("{base}/redirect"))
            .send()
            .await
            .expect_err("HTTP redirect destination must be rejected for hosted providers");
        assert!(
            error.is_redirect(),
            "expected a redirect-policy error: {error}"
        );
        let message = policy_message(&error);
        assert!(
            message.contains("non-HTTPS destination"),
            "unexpected error message: {message}"
        );
    }

    #[tokio::test]
    async fn hosted_policy_rejects_cross_host_https_redirect() {
        // Cross-host HTTPS is still outside the approved origin. The client
        // must reject it before connecting to the foreign host.
        let address = spawn_redirect_server("https://cdn.openai.com/v1/models");
        let base = format!("http://{address}");
        let client = client_with(hosted_provider_redirect_policy());
        let error = client
            .get(format!("{base}/redirect"))
            .send()
            .await
            .expect_err("cross-host redirect must be rejected for hosted providers");
        assert!(
            error.is_redirect(),
            "expected a redirect-policy error: {error}"
        );
        let message = policy_message(&error);
        assert!(
            message.contains("must stay on the approved origin"),
            "unexpected error message: {message}"
        );
    }

    #[tokio::test]
    async fn policy_bounds_redirect_chains_to_max_hops() {
        let address = spawn_redirect_server("/final");
        let base = format!("http://{address}");
        let client = client_with(ollama_redirect_policy());
        // `/hop/1` redirects to `/hop/2` → … forever; only the hop bound stops it.
        let error = client
            .get(format!("{base}/hop/1"))
            .send()
            .await
            .expect_err("an unbounded redirect loop must be stopped by the hop bound");
        assert!(
            error.is_redirect(),
            "expected a redirect-policy error: {error}"
        );
        let message = policy_message(&error);
        assert!(
            message.contains("exceeded 5 hops"),
            "unexpected error message: {message}"
        );
    }

    // ── Curated catalog regime dispatch ─────────────────────────────────────

    #[test]
    fn curated_dispatch_applies_ollama_regime_to_ollama_origin() {
        let original = ollama_original();
        // Local destination: followed under the Ollama regime.
        let next = url("http://127.0.0.1:11434/api/chat");
        assert_eq!(
            curated_redirect_allowed(&next, &original, Some("ollama")),
            Ok(())
        );
        // Public destination: rejected under the Ollama regime.
        let public = url("https://ollama.example.com/api/chat");
        assert_eq!(
            curated_redirect_allowed(&public, &original, Some("ollama")),
            Err(RedirectViolation::NonLocalDestination {
                destination: public.to_string(),
            })
        );
    }

    #[test]
    fn curated_dispatch_applies_hosted_regime_to_hosted_origin() {
        let original = hosted_original();
        // Same-origin HTTPS: followed under the hosted regime.
        let next = url("https://api.openai.com/v1/chat/completions/retry");
        assert_eq!(
            curated_redirect_allowed(&next, &original, Some("ollama")),
            Ok(())
        );
        // HTTP destination: rejected under the hosted regime.
        let plain = url("http://api.openai.com/v1/chat/completions");
        assert_eq!(
            curated_redirect_allowed(&plain, &original, Some("ollama")),
            Err(RedirectViolation::NonHttps {
                destination: plain.to_string(),
            })
        );
    }

    #[test]
    fn curated_dispatch_with_unknown_ollama_host_degrades_to_hosted() {
        let original = hosted_original();
        let next = url("https://api.openai.com/v1/other");
        // `None` (unparseable curated Ollama URL) must not open the local-only
        // regime for arbitrary origins — the safe default is hosted.
        assert_eq!(curated_redirect_allowed(&next, &original, None), Ok(()));
        let plain = url("http://api.openai.com/v1/other");
        assert_eq!(
            curated_redirect_allowed(&plain, &original, None),
            Err(RedirectViolation::NonHttps {
                destination: plain.to_string(),
            })
        );
    }
}
