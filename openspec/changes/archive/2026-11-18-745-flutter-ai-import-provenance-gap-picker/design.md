<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: glm-5.4 (opencode-go) -->

# Design — Flutter AI import Pass-2 provenance & gap picker (issue #745)

## Decisions

### D1 — The origin is read, never re-derived

`DraftOutfit.origin` is a plain four-value wire string and
`DraftOutfit.provenance` carries the Pass-2 payload (source draft ref, source
scene number, confidence). The client maps the origin to ONE localized badge
and takes the scene number from the provenance; it never infers provenance
from the presence of a quote, a scene number or a confidence value.

An absent origin (a preview stored before the field existed) and an
unrecognized future value render **nothing**. Rendering a fallback badge would
attribute a look to a source the wire never named.

### D2 — A Pass-2 look shows no source quote

The server leaves `source_quote` empty for a continued or inferred look: there
is no chunk to quote (the source row carries the quote for a continuation, and
the inference has no script sentence at all). The client suppresses the quote
line for exactly those two origins.

Showing `Beleg: ` with nothing behind it is worse than showing nothing: the
reviewer is asked to verify an extraction against the script, and an empty
evidence line implies the script was silent about a look it never mentioned.

A `derived` Pass-1 look keeps its quote: it was derived *from a quoted
fragment*, which is different from a Pass-2 look derived from scene context.

### D3 — Only script-derivable candidates are offered (picker placement: preview rows)

The gap card replaces the plain uncertainty notice for a `dropped_row`
uncertainty on `outfits` **whose `candidates` list is non-empty**; a gap
without candidates keeps the notice. Nothing is ever offered beyond the
server's list, and the note prose stays visible verbatim above the chips.

The picker lives where the gap notice renders (the preview row list) rather
than in the apply card: the reviewer decides about a *scene*, so the scene
label and the surrounding extracted rows stay in view. The apply card then
repeats the resolution at the dispatch point (D5), mirroring the #581 group
targets and #706 day decisions.

`ChoiceChip`s are used instead of radio rows: one tap resolves a gap, the
selected state is explicit, and the widget avoids the `Radio`/`RadioGroup`
API churn that would otherwise pin the client to a Flutter version for no
user-visible gain.

### D4 — `character_identity` is derived from the gap's own scene

The wire uncertainty carries `scene_index`, `note` and `candidates` — but no
`character_identity`, and the server validates the selection against the
preview's own gap derivation (`409 ai-import.apply-unknown-continuity-candidate`
for anything else). The client therefore reproduces the backend's derivation:

1. **The scene's undressed figures:** characters the scene names for whom the
   scene carries no outfit, compared by `characterIdentity()` (case-folded,
   whitespace-collapsed — the backend's `character_identity`), deduplicated in
   document order.
2. **The pairing:** resolve the uncertainty's `continued` candidate's
   `source_draft_ref` back to that source row and ask which of the scene's
   undressed figures that row dresses. When several of them appeared there,
   the candidate's look name is the tie-breaker the server derived it from.
   The `note` prose is never parsed.
3. **Honest degradation:** an uncertainty whose figure cannot be resolved is
   dropped, and the plain notice renders instead of a pick the server would
   refuse. An *inferred-only* candidate list is the Option-B notice of a figure
   the pass already dressed — the server no longer reports it as a gap, so it
   is never offered.

`characterIdentity()` is used for MATCHING only: the created `Character` keeps
the script's verbatim spelling, which is why `ContinuityGap` carries both.

### D5 — A pick is a review edit, and the dispatch says what it will do

`continuity_selections` travels next to `mappings`, `episode_groups`,
`shooting_days` and `uncertainty_acknowledgements`, absent when nothing was
picked (the request then stays byte-identical to the pre-#745 client).

A pick changes what the apply creates — a look for a figure the script left
undressed — so it counts in `edit_distance` and breaks `accept_as_is`, exactly
like a rejected look or a rejected day. Claiming "applied unchanged" over a
reviewer's wardrobe decision would be a false statement about the review; the
backend rejects the combination anyway.

The apply card repeats each gap as `Szene N · Figur → Look` (the candidate's own
name) or `… → ohne Look (bewusst leer)`, so the EU AI Act review gate keeps
holding at the dispatch point.

### D6 — `AiApplyState.copyWith` replaces hand-written re-construction

Every reviewer decision (`decide`, `decideOutfit`, `setGroupTarget`,
`decideDay`, `acknowledgeUncertainty`, `setContext`, `setCommandError`,
`dismissCommandError`, `decideContinuityGap`) previously re-constructed the
whole state field by field. Two of those sites (`setCommandError`,
`dismissCommandError`) forgot `dayDecisions`, so surfacing any command error
silently reset the #706 day toggles. The new `copyWith` (sentinel-based, so
`null` stays expressible for the nullable fields) makes each mutation state
exactly what it changes — which is also what keeps the two new fields
(gaps, picks) from being forgotten at the next site.
