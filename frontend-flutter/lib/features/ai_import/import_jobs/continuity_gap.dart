// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.4 (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';

/// Pure, Flutter-free derivation of the reviewer-selectable wardrobe gaps
/// (OpenSpec `ai-import-decision-outfit-continuity`, issue #745).
///
/// The server's Pass 2 reports a gap as a `dropped_row` uncertainty on the
/// `outfits` field whose `candidates` list carries the looks the SCRIPT
/// actually supports (design D4). The wire carries no `character_identity` on
/// that uncertainty, so the reviewer's pick — which the apply request sends as
/// `OutfitContinuitySelection { scene_index, character_identity, candidate }` —
/// has to be addressed from preview data alone. This module does exactly that,
/// mirroring the backend's own derivation:
///
/// * a **gap figure** is a character the scene names for whom the scene carries
///   no outfit (compared by [characterIdentity], the preview-wide matching key);
/// * the uncertainty is paired with that figure by resolving its `continued`
///   candidate's `source_draft_ref` back to the source row and asking WHICH
///   gap figure of this scene that row dresses (the candidate's look name is
///   the tie-breaker) — never by reading the `note` prose;
/// * an inferred-only candidate list is an Option-B **notice** (the pass already
///   attached that look, so the server no longer reports the figure as a gap)
///   and is therefore never offered as a pick.
///
/// Nothing here invents a gap: an uncertainty whose figure cannot be resolved
/// from the preview is dropped, and the plain notice keeps rendering instead of
/// a pick the server would refuse with `409
/// ai-import.apply-unknown-continuity-candidate`.

/// The wire `field` Pass 2 attaches a wardrobe-gap uncertainty to.
const String continuityGapField = 'outfits';

/// The preview-wide matching key of a figure: case-folded and
/// whitespace-collapsed, exactly like the backend's `character_identity`.
///
/// Only ever used for MATCHING (gap pairing and the apply request's
/// `character_identity`); what gets created as a `Character` name stays the
/// script's verbatim wording.
String characterIdentity(String name) {
  final out = StringBuffer();
  var pendingSpace = false;
  for (final rune in name.runes) {
    if (_isUnicodeWhitespace(rune)) {
      pendingSpace = out.isNotEmpty;
      continue;
    }
    if (pendingSpace) {
      out.write(' ');
      pendingSpace = false;
    }
    out.write(String.fromCharCode(rune).toLowerCase());
  }
  return out.toString();
}

/// The Unicode `White_Space` property — exactly the set Rust's
/// `char::is_whitespace()` uses, so both sides fold a name onto the SAME
/// identity key.
///
/// Dart's `RegExp(r'\s')` is NOT that set: ECMAScript `\s` counts the BOM
/// (U+FEFF) as whitespace and misses NEL (U+0085), so a name containing either
/// would produce a key the server does not derive — and the apply would answer
/// `409 ai-import.apply-unknown-continuity-candidate` for a correct pick.
bool _isUnicodeWhitespace(int rune) =>
    (rune >= 0x09 && rune <= 0x0D) ||
    rune == 0x20 ||
    rune == 0x85 ||
    rune == 0xA0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000;

/// The mapping reference of one draft row, mirroring the backend's
/// `draft_row_ref`: a row the model left without a reference is addressed by
/// its position, so the candidate's `source_draft_ref` resolves either way.
String draftRowRef(DraftScene scene, int index) =>
    scene.draftRef.isEmpty ? 'scene-$index' : scene.draftRef;

/// One wardrobe gap the reviewer may resolve with a single pick.
final class ContinuityGap {
  const ContinuityGap({
    required this.uncertaintyIndex,
    required this.sceneIndex,
    required this.sceneNumber,
    required this.characterIdentity,
    required this.characterName,
    required this.note,
    required this.candidates,
  });

  /// Index of the source uncertainty in the preview's `uncertainties` list —
  /// the exact position a surface matches this gap back to, so two
  /// uncertainties that happen to share scene and note text can never render
  /// two cards for one gap (duplicate widget keys).
  final int uncertaintyIndex;

  /// Index of the gap scene in the preview's `scenes` list — the same index the
  /// gap uncertainty and the apply request's selection carry.
  final int sceneIndex;

  /// The scene's document number, when it has one (display only).
  final int? sceneNumber;

  /// The figure's preview-wide identity key — what the selection sends.
  final String characterIdentity;

  /// The figure's name as this scene wrote it (display only).
  final String characterName;

  /// The server's own uncertainty note, rendered verbatim (never parsed).
  final String note;

  /// The looks the script supports, in the server's order. Never empty — a gap
  /// without candidates is a plain notice, not a selectable gap.
  final List<DraftOutfitCandidate> candidates;

  /// The candidate that continues the figure's most recent earlier look, when
  /// the script supports one.
  DraftOutfitCandidate? get continued =>
      _firstOf(DraftOutfitOrigin.continuedFromScene);

  /// The candidate derived from the scene's own context, when it exists.
  DraftOutfitCandidate? get inferred =>
      _firstOf(DraftOutfitOrigin.inferredFromContext);

  DraftOutfitCandidate? _firstOf(DraftOutfitOrigin origin) {
    for (final candidate in candidates) {
      if (candidate.origin == origin) return candidate;
    }
    return null;
  }
}

/// Every reviewer-selectable wardrobe gap of [context], in the wire's
/// uncertainty order.
///
/// Empty for a preview stored before Pass 2 existed, and for a preview whose
/// gaps carried no script-derivable candidate (design D4 case C2) — both keep
/// rendering the plain gap notice, never an invented option.
List<ContinuityGap> continuityGapsOf(ScriptContext context) {
  final scenes = context.scenes;
  final sceneByDraftRef = <String, DraftScene>{
    for (final (index, scene) in scenes.indexed)
      draftRowRef(scene, index): scene,
  };
  // Per scene: the figures the scene names but does not dress, in document
  // order — the backend's `outfit_continuity_gaps` shape restricted to what a
  // stored preview can still tell (the plausible-action gate decided which
  // gaps were evaluated at all; a reported gap therefore passed it).
  final gapIdentities = <int, List<String>>{
    for (final (index, scene) in scenes.indexed)
      index: _undressedIdentities(scene),
  };

  final gaps = <ContinuityGap>[];
  final seen = <String>{};
  for (final (index, uncertainty) in context.uncertainties.indexed) {
    final candidates = uncertainty.candidates;
    if (uncertainty.field != continuityGapField ||
        uncertainty.kind != UncertaintyKind.droppedRow ||
        candidates == null ||
        candidates.isEmpty) {
      continue;
    }
    final sceneIndex = uncertainty.sceneIndex;
    if (sceneIndex < 0 || sceneIndex >= scenes.length) continue;
    final scene = scenes[sceneIndex];
    final undressed = gapIdentities[sceneIndex] ?? const <String>[];
    if (undressed.isEmpty) continue;

    final identity = _identityOfGap(
      candidates: candidates.toList(),
      scene: scene,
      undressed: undressed,
      sceneByDraftRef: sceneByDraftRef,
    );
    if (identity == null) continue;
    // Two selections for one gap are refused by the server: keep the first.
    if (!seen.add('$sceneIndex\u0000$identity')) continue;

    gaps.add(
      ContinuityGap(
        uncertaintyIndex: index,
        sceneIndex: sceneIndex,
        sceneNumber: scene.sceneNumber,
        characterIdentity: identity,
        characterName: _verbatimName(scene, identity),
        note: uncertainty.note,
        candidates: candidates.toList(),
      ),
    );
  }
  return gaps;
}

/// The figure one gap uncertainty belongs to, or `null` when the preview does
/// not let the client tell (never a guess).
String? _identityOfGap({
  required List<DraftOutfitCandidate> candidates,
  required DraftScene scene,
  required List<String> undressed,
  required Map<String, DraftScene> sceneByDraftRef,
}) {
  DraftOutfitCandidate? continued;
  for (final candidate in candidates) {
    if (candidate.origin == DraftOutfitOrigin.continuedFromScene) {
      continued = candidate;
      break;
    }
  }
  // An inferred-only list is the Option-B notice of a figure the pass already
  // dressed: the server's gap list no longer carries it, so offering the pick
  // would earn a 409 at the apply.
  if (continued == null) return null;

  final source = sceneByDraftRef[continued.sourceDraftRef];
  if (source != null) {
    final dressed = <String>{
      for (final outfit in source.outfits ?? <DraftOutfit>[])
        characterIdentity(outfit.characterName),
    };
    final matches = [
      for (final identity in undressed)
        if (dressed.contains(identity)) identity,
    ];
    if (matches.length == 1) return matches.single;
    // Several of the scene's gap figures appeared in the source row: the
    // candidate's look name is the tie-breaker the server derived it from.
    final lookName = characterIdentity(continued.name);
    final named = <String>{
      for (final outfit in source.outfits ?? <DraftOutfit>[])
        if (characterIdentity(outfit.name) == lookName)
          characterIdentity(outfit.characterName),
    };
    final namedMatches = [
      for (final identity in undressed)
        if (named.contains(identity)) identity,
    ];
    if (namedMatches.length == 1) return namedMatches.single;
    return null;
  }
  // The source row is not part of this preview (a corrupt or hand-built
  // payload): only an unambiguous gap can still be addressed.
  return undressed.length == 1 ? undressed.single : null;
}

/// The scene's figures without an outfit, by identity, in document order.
List<String> _undressedIdentities(DraftScene scene) {
  final dressed = <String>{
    for (final outfit in scene.outfits ?? <DraftOutfit>[])
      characterIdentity(outfit.characterName),
  };
  final identities = <String>[];
  for (final character in scene.characters ?? <DraftCharacter>[]) {
    final identity = characterIdentity(character.name);
    if (identity.isEmpty ||
        dressed.contains(identity) ||
        identities.contains(identity)) {
      continue;
    }
    identities.add(identity);
  }
  return identities;
}

/// The scene's own wording of [identity] (never the normalized key).
String _verbatimName(DraftScene scene, String identity) {
  for (final character in scene.characters ?? <DraftCharacter>[]) {
    if (characterIdentity(character.name) == identity) return character.name;
  }
  return identity;
}
