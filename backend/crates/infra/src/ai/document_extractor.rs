// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Runtime selection of the document-structure adapter (ADR-041 `D1`, issue
//! #958).
//!
//! The two import workers are generic over
//! [`DocumentStructureExtractor`] and dispatch **statically**, so "which parser
//! is configured?" has to be answered exactly once, in the composition root,
//! where the environment is read. [`ConfiguredDocumentExtractor`] is that
//! answer: a plain `Clone` enum, built once in `main.rs`, stored in
//! [`WorkerDeps`](super::worker_loop::WorkerDeps) **by value** and cheaply
//! cloned per job tick.
//!
//! It exists so that a missing/`spatial` configuration never has to be a
//! `Option<Box<dyn ...>>`:
//!
//! * `Spatial`/`Legacy` are `Copy` two-word configs — no allocation at all;
//! * `Docling` holds a `reqwest::Client`, which is *already* an internal `Arc`,
//!   so the clone is a pointer bump;
//! * dispatch is a `match` on a discriminant — no vtable, no
//!   `Arc<dyn DocumentStructureExtractor>`.

use std::time::Duration;

use breakdown_core::ai::{
    AiImportBounds, DocumentStructureExtractor, ExtractionOptions, LlmProvider, RenderOptions,
    RenderedPage, StructuredDocument,
};
use breakdown_core::error::DomainError;
use reqwest::Url;

use super::docling::DoclingHttpAdapter;
use super::pdf::LegacyPdfToTextAdapter;
use super::spatial_pdf::SpatialPdfExtractor;
use super::transport::curated_provider_redirect_policy;
use super::user_agent::resolve_user_agent;

/// Environment variable selecting the document-structure adapter.
pub const AI_DOCUMENT_PARSER_ENV: &str = "AI_DOCUMENT_PARSER";

/// Environment variable carrying the `docling-serve` base URL. Required only
/// when [`AI_DOCUMENT_PARSER_ENV`] selects `docling`.
pub const AI_DOCLING_ENDPOINT_ENV: &str = "AI_DOCLING_ENDPOINT";

/// The configured parser, without the adapter instances.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum DocumentParser {
    /// Poppler `-bbox-layout` + on-demand page renders (ADR-041 default).
    #[default]
    Spatial,
    /// A self-hosted `docling-serve` sidecar; adds `<table>` markup.
    Docling,
    /// The pre-ADR-041 flat-text path. The rollback target.
    LegacyPdfToText,
}

impl DocumentParser {
    /// The `AI_DOCUMENT_PARSER` spelling of this parser.
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Spatial => "spatial",
            Self::Docling => "docling",
            Self::LegacyPdfToText => "legacy-pdftotext",
        }
    }

    /// Parse one `AI_DOCUMENT_PARSER` value. `None` means "not a known parser" —
    /// the caller decides whether that is fatal (it is: a typo must not silently
    /// select a different extraction path).
    #[must_use]
    pub fn parse(value: &str) -> Option<Self> {
        match value.trim().to_ascii_lowercase().as_str() {
            "" => Some(Self::default()),
            "spatial" | "poppler-spatial" => Some(Self::Spatial),
            "docling" | "docling-http" => Some(Self::Docling),
            "legacy" | "legacy-pdftotext" => Some(Self::LegacyPdfToText),
            _ => None,
        }
    }

    /// Read [`AI_DOCUMENT_PARSER_ENV`]; an unset value defaults to
    /// [`Self::Spatial`], an unrecognised one is a startup error.
    pub fn from_env() -> Result<Self, DomainError> {
        match std::env::var(AI_DOCUMENT_PARSER_ENV) {
            Ok(value) => Self::parse(&value).ok_or_else(|| {
                DomainError::validation(format!(
                    "{AI_DOCUMENT_PARSER_ENV}=\"{value}\" is not a known document parser; \
                     use spatial, docling or legacy-pdftotext"
                ))
            }),
            Err(_) => Ok(Self::default()),
        }
    }
}

/// The adapter actually wired into the import workers.
#[derive(Clone, Debug)]
pub enum ConfiguredDocumentExtractor {
    Spatial(SpatialPdfExtractor),
    Docling(DoclingHttpAdapter),
    Legacy(LegacyPdfToTextAdapter),
}

impl ConfiguredDocumentExtractor {
    /// Build the extractor selected by the environment, once, at startup.
    ///
    /// The bound and timeout knobs come from [`AiImportBounds`], so a document
    /// tool is subject to the same ceilings as the rest of the pipeline rather
    /// than to private constants.
    pub fn from_env(bounds: &AiImportBounds) -> Result<Self, DomainError> {
        Self::from_parser(DocumentParser::from_env()?, bounds)
    }

    /// Build the extractor for an explicit [`DocumentParser`], reading the
    /// `docling` endpoint from the environment.
    pub fn from_parser(
        parser: DocumentParser,
        bounds: &AiImportBounds,
    ) -> Result<Self, DomainError> {
        Self::build(
            parser,
            bounds,
            std::env::var(AI_DOCLING_ENDPOINT_ENV).ok().as_deref(),
        )
    }

    /// The env-free builder. Exposed to the sibling tests so the endpoint
    /// validation is testable without mutating process-global state.
    fn build(
        parser: DocumentParser,
        bounds: &AiImportBounds,
        docling_endpoint: Option<&str>,
    ) -> Result<Self, DomainError> {
        let max_output_bytes = usize::try_from(bounds.max_document_bytes).unwrap_or(usize::MAX);
        let timeout = Duration::from_secs(bounds.request_timeout_secs);
        match parser {
            DocumentParser::Spatial => Ok(Self::Spatial(SpatialPdfExtractor::new(
                max_output_bytes,
                timeout,
            ))),
            DocumentParser::LegacyPdfToText => Ok(Self::Legacy(LegacyPdfToTextAdapter::new(
                max_output_bytes,
                timeout,
            ))),
            DocumentParser::Docling => {
                let endpoint = docling_endpoint.ok_or_else(|| {
                    DomainError::validation(format!(
                        "{AI_DOCUMENT_PARSER_ENV}=docling requires {AI_DOCLING_ENDPOINT_ENV} \
                         (e.g. http://docling:5001/)"
                    ))
                })?;
                let base_url = Url::parse(endpoint.trim()).map_err(|error| {
                    DomainError::validation(format!(
                        "{AI_DOCLING_ENDPOINT_ENV}=\"{endpoint}\" is not a URL: {error}"
                    ))
                })?;
                validate_docling_base_url(&base_url)?;
                // The sidecar is an internal service: no proxy, no cross-host
                // redirect (ADR-024 policy) and no credential to carry.
                let client = reqwest::Client::builder()
                    .timeout(timeout)
                    .redirect(curated_provider_redirect_policy())
                    .no_proxy()
                    .user_agent(resolve_user_agent(LlmProvider::Ollama))
                    .build()
                    .map_err(|error| {
                        DomainError::service_unavailable(format!(
                            "could not build the docling HTTP client: {error}"
                        ))
                    })?;
                Ok(Self::Docling(DoclingHttpAdapter::new(
                    client,
                    base_url,
                    max_output_bytes,
                    timeout,
                )))
            }
        }
    }

    /// Which parser this extractor implements.
    #[must_use]
    pub const fn parser(&self) -> DocumentParser {
        match self {
            Self::Spatial(_) => DocumentParser::Spatial,
            Self::Docling(_) => DocumentParser::Docling,
            Self::Legacy(_) => DocumentParser::LegacyPdfToText,
        }
    }
}

/// Reject a base URL the adapter cannot build a conversion request from.
///
/// `Url::parse` accepts far more than this adapter can use: `mailto:operator@…`
/// parses, but it is not a *base* URL, so joining the conversion path fails on
/// every upload; and a slashless path prefix (`http://host/ds`) makes
/// `join("v1/convert/source")` replace the prefix instead of appending to it.
/// Both are configuration errors, so they fail the boot rather than the first
/// import.
fn validate_docling_base_url(base_url: &Url) -> Result<(), DomainError> {
    if !matches!(base_url.scheme(), "http" | "https") {
        return Err(DomainError::validation(format!(
            "{AI_DOCLING_ENDPOINT_ENV}=\"{base_url}\" must be an http(s) URL"
        )));
    }
    if base_url.cannot_be_a_base() || base_url.host().is_none() {
        return Err(DomainError::validation(format!(
            "{AI_DOCLING_ENDPOINT_ENV}=\"{base_url}\" is not an absolute base URL"
        )));
    }
    if !base_url.path().ends_with('/') {
        return Err(DomainError::validation(format!(
            "{AI_DOCLING_ENDPOINT_ENV}=\"{base_url}\" must end with a slash, so the \
             conversion path is appended to its path prefix instead of replacing it"
        )));
    }
    Ok(())
}

impl DocumentStructureExtractor for ConfiguredDocumentExtractor {
    fn parser_fingerprint(&self) -> &'static str {
        match self {
            Self::Spatial(extractor) => extractor.parser_fingerprint(),
            Self::Docling(extractor) => extractor.parser_fingerprint(),
            Self::Legacy(extractor) => extractor.parser_fingerprint(),
        }
    }

    async fn extract(
        &self,
        bytes: &[u8],
        options: ExtractionOptions,
    ) -> Result<StructuredDocument, DomainError> {
        match self {
            Self::Spatial(extractor) => extractor.extract(bytes, options).await,
            Self::Docling(extractor) => extractor.extract(bytes, options).await,
            Self::Legacy(extractor) => extractor.extract(bytes, options).await,
        }
    }

    async fn render_page(
        &self,
        bytes: &[u8],
        page_number: u32,
        options: RenderOptions,
    ) -> Result<RenderedPage, DomainError> {
        match self {
            Self::Spatial(extractor) => extractor.render_page(bytes, page_number, options).await,
            Self::Docling(extractor) => extractor.render_page(bytes, page_number, options).await,
            Self::Legacy(extractor) => extractor.render_page(bytes, page_number, options).await,
        }
    }
}

#[cfg(test)]
#[path = "document_extractor_tests.rs"]
mod document_extractor_tests;
