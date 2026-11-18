<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: space-bunny-free (opencode-go) -->

# Proposal: AI-import input, model editing, and prompt-default editing (issues #508, #509, #520)

## Summary

Combine the three closely related AI-import usability gaps in one Flutter-client
change:

1. make Script the default document kind and make Schedule file-only;
2. allow provider, assistant-model, and image-model changes in the configured
   AI-config form;
3. use backend prompt defaults as fallbacks for configured prompts whose stored
   value is empty, and render both prompt kinds in an editable XML-highlighted
   editor.

No backend or OpenAPI schema change is required.

## Decisions

- Schedule accepts only a picked `.csv` or `.pdf`; the paste field and its
  transient controller state are removed rather than hidden.
- Script is the initial kind and is ordered before Schedule in the segmented
  control.
- The configured form reuses the existing model discovery and picker
  components. Its provider is displayed but locked to the vault-bound provider
  because the backend aggregate rejects a provider change paired with the old
  vault key. Assistant model, optional image model, prompts, and the fetched
  optimistic-lock version remain editable. Provider replacement is tracked in
  issue #528 and requires a backend credential hand-off.
- A non-empty stored prompt always wins. When a configured prompt is absent or
  empty, `GET /v1/ai-import/defaults` supplies the editable fallback. An
  untouched save therefore persists that default; a user edit remains
  authoritative, including an explicit clear.
- Prompt editing uses `flutter_code_editor` 0.3.5 with the `highlight` XML
  grammar. Highlighting is presentation-only: controllers carry the exact XML
  source into the existing prompt draft state and PATCH payload.
- Editor token colors are derived from Material 3 `ColorScheme` roles so the
  component remains light/dark aware without feature-local color literals.

## Validation

- Widget tests prove Script default/order and the absence of a schedule paste
  affordance.
- The schedule CSV mapping/upload wire seam is tested to carry UTF-8-decoded CSV
  with `AiScheduleSource.csv` to the schedule upload path.
- Configured-form widget tests prove model editing and the PATCH body, prompt
  fallback precedence, exact saved XML, XML token styling, provider locking,
  and prompt-only edits when provider discovery is unavailable.
- Existing conflict, first-run, stored-prompt, and configured-form goldens are
  updated to the new editor/model-editor layout.

## Non-goals

- No backend endpoint, generated OpenAPI client, or Drift schema change.
- No offline prompt drafts.
- No new localization copy; existing labels and error narratives are reused.
