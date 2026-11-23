// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

//! Minimal markup helpers shared by the document-structure adapters
//! (issue #958).
//!
//! Both HTTP/subprocess adapters receive *generated* markup — Poppler's
//! `-bbox-layout` XHTML and Docling's HTML export — never human-authored pages
//! with scripts, comments or CDATA. That makes a small total (never panicking)
//! scanner the right tool: a full HTML parser would be a dependency the input
//! cannot justify.
//!
//! Two rules keep the text honest, because downstream `verify_draft_outfits`
//! compares quoted text verbatim:
//!
//! * an entity the decoder does not know is **kept verbatim**, never dropped;
//! * `strip_tags` removes markup only — it never collapses whitespace on its
//!   own, so a caller decides how much layout it wants to keep.

/// Decode the XML/HTML entities Poppler and Docling emit (`&amp;`, `&lt;`,
/// `&gt;`, `&quot;`, `&apos;` plus numeric character references).
#[must_use]
pub(crate) fn decode_entities(text: &str) -> String {
    if !text.contains('&') {
        return text.to_owned();
    }
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        let tail = &rest[amp..];
        let Some(semicolon) = tail.find(';') else {
            out.push_str(tail);
            return out;
        };
        let entity = &tail[1..semicolon];
        match entity {
            "amp" => out.push('&'),
            "lt" => out.push('<'),
            "gt" => out.push('>'),
            "quot" => out.push('"'),
            "apos" => out.push('\''),
            "nbsp" => out.push(' '),
            _ => match numeric_entity(entity) {
                Some(character) => out.push(character),
                // Unknown entity: keep it verbatim rather than silently eating
                // text that may matter to a verbatim quote check.
                None => out.push_str(&tail[..=semicolon]),
            },
        }
        rest = &tail[semicolon + 1..];
    }
    out.push_str(rest);
    out
}

/// `#65` / `#x41` → `A`.
fn numeric_entity(entity: &str) -> Option<char> {
    let digits = entity.strip_prefix('#')?;
    let code = match digits
        .strip_prefix('x')
        .or_else(|| digits.strip_prefix('X'))
    {
        Some(hex) => u32::from_str_radix(hex, 16).ok()?,
        None => digits.parse::<u32>().ok()?,
    };
    char::from_u32(code)
}

/// Remove every `<...>` tag, keeping the text between tags and decoding
/// entities. An unterminated `<` keeps the remainder verbatim.
#[must_use]
pub(crate) fn strip_tags(markup: &str) -> String {
    let mut out = String::with_capacity(markup.len());
    let mut rest = markup;
    while let Some(open) = rest.find('<') {
        out.push_str(&rest[..open]);
        let tail = &rest[open..];
        let Some(close) = tail.find('>') else {
            out.push_str(tail);
            return decode_entities(&out);
        };
        // A tag is one line at most; a `<` further away than the next line
        // break is text (e.g. "a < b"), not markup.
        let newline = tail.find('\n');
        if newline.is_some_and(|index| index < close) {
            out.push('<');
            rest = &tail[1..];
            continue;
        }
        rest = &tail[close + 1..];
    }
    out.push_str(rest);
    decode_entities(&out)
}

/// Collapse every whitespace run into a single space and trim the result.
#[must_use]
pub(crate) fn collapse_whitespace(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::{collapse_whitespace, decode_entities, strip_tags};

    #[test]
    fn known_and_numeric_entities_decode() {
        assert_eq!(decode_entities("a &amp;lt; b"), "a &lt; b");
        assert_eq!(decode_entities("&#65;&#x42;"), "AB");
        assert_eq!(decode_entities("&nbsp;x"), " x");
        assert_eq!(decode_entities("plain"), "plain");
        assert_eq!(decode_entities("dangling &"), "dangling &");
    }

    #[test]
    fn unknown_entities_are_preserved_verbatim() {
        assert_eq!(decode_entities("a &foo; b"), "a &foo; b");
        assert_eq!(decode_entities("&#xZZ;"), "&#xZZ;");
    }

    #[test]
    fn strip_tags_keeps_text_and_drops_markup() {
        assert_eq!(
            strip_tags("<p>Hallo <b>Welt</b></p><p>zwei</p>"),
            "Hallo Weltzwei"
        );
        assert_eq!(strip_tags("a &amp; b"), "a & b");
        assert_eq!(strip_tags(""), "");
    }

    #[test]
    fn strip_tags_does_not_eat_a_comparison_operator() {
        // "a < b" on one line is text; the scan restarts after the `<`.
        assert_eq!(strip_tags("a < b"), "a < b");
    }

    #[test]
    fn an_unterminated_tag_keeps_the_remainder() {
        assert_eq!(strip_tags("<p>ok</p><b>dangling"), "okdangling");
    }

    #[test]
    fn collapse_whitespace_normalizes_runs() {
        assert_eq!(collapse_whitespace("  a \n\t b  "), "a b");
        assert_eq!(collapse_whitespace("   "), "");
    }
}
