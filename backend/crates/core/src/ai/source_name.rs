// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Display normalization of an uploaded document's file name (issue #763).
//!
//! The AI-import upload is a **raw body** with no metadata envelope, so the
//! name of the picked document travels as an optional HTTP header and is
//! converted here, once, into the value the job row stores and every client
//! renders. Everything a browser or a caller could smuggle in — a path, a
//! newline, half a megabyte of padding — is removed rather than truncated into
//! something that looks intentional.

/// Maximum length of a persisted display name, in `char`s.
///
/// The cap is deliberately below the 255-byte filesystem convention so a
/// multi-byte (CJK, emoji, umlaut) name cannot be cut mid-character by a
/// downstream byte-oriented limit. Overflow is trimmed on a `char` boundary
/// and the value is then trimmed again, so a trailing space never survives.
pub const MAX_SOURCE_FILE_NAME_CHARS: usize = 200;

/// Normalize a raw (already percent-decoded) document name into the display
/// name persisted on the job, or `None` when nothing printable remains.
///
/// Rules, in order:
/// 1. **Basename only** — everything up to and including the last `/` or `\`
///    is dropped, so `../../etc/passwd` and `C:\docs\script.pdf` reduce to
///    `passwd` / `script.pdf`. A caller's directory layout is not display data.
/// 2. **Control characters removed** — `char::is_control` covers C0, DEL and
///    the C1 range, which is what makes a header injection or a log-forging
///    attempt impossible to round-trip.
/// 3. **Whitespace collapsed** — runs of whitespace (including non-breaking
///    and other Unicode spaces) become one ASCII space; the value is trimmed.
/// 4. **Bounded** — at most [`MAX_SOURCE_FILE_NAME_CHARS`] characters, trimmed
///    again after the cut.
/// 5. **Empty is absent** — `""`, `"   "`, `"."` and `".."` yield `None`; a
///    blank-looking name is never stored as a name.
#[must_use]
pub fn sanitize_source_file_name(raw: &str) -> Option<String> {
    // (1) basename: keep everything after the last path separator.
    let basename = raw
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(raw)
        // (2) drop control characters before whitespace collapsing, so a
        // `\r\n` cannot masquerade as a line break inside the value.
        .chars()
        .filter(|ch| !ch.is_control())
        // (3) collapse every whitespace run into a single space.
        .fold(String::new(), |mut acc, ch| {
            if ch.is_whitespace() {
                if !acc.ends_with(' ') && !acc.is_empty() {
                    acc.push(' ');
                }
            } else {
                acc.push(ch);
            }
            acc
        });
    let trimmed = basename.trim();
    // (5) the two path-relative sentinels are not names.
    if trimmed.is_empty() || trimmed == "." || trimmed == ".." {
        return None;
    }
    // (4) char-boundary safe cap, then re-trim: a cut may leave a trailing
    // space that was interior before truncation.
    let capped: String = trimmed.chars().take(MAX_SOURCE_FILE_NAME_CHARS).collect();
    let capped = capped.trim_end();
    if capped.is_empty() {
        return None;
    }
    Some(capped.to_string())
}

#[cfg(test)]
#[path = "source_name_tests.rs"]
mod source_name_tests;
