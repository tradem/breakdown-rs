// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

/// Pure Karl Klammer trigger logic (issue #516, Decision D4 of
/// `add-karl-klammer-easter-egg`): maps an AI-Import flow state to a tip
/// (copy key) + pose. Deterministic — no wall clock, no randomness, no
/// Flutter imports (Tier-1 unit testable).
///
/// The widget layer resolves the [ClippyTipKey] via l10n
/// (`aiImport.clippy.*` ARB keys) and renders the [ClippyPose] with the
/// programmatic hanger figure.
library;

/// The AI-Import flow states Karl Klammer reacts to (issue §C).
enum ClippyFlowState {
  /// No AI config present yet — the "It looks like you're writing a
  /// letter…" allusion offering the AI-config entry.
  noConfig,

  /// An import job is running — Clippy's signature eager-for-knowledge
  /// animation, adapted to the hanger: an excited swing/wobble.
  running,

  /// The import failed — a consoling gesture (the hanger droops).
  error,

  /// The import succeeded — the hanger "proudly wears" the result.
  success,

  /// Nothing notable happening — occasional jokes from the Clippy canon
  /// (deterministically cycled by the trigger count; the tick itself
  /// comes from the overlay's injectable idle clock).
  idle,
}

/// The figure's pose — drives the painter's geometry and animation.
enum ClippyPose {
  /// Resting pose, hook upright.
  neutral,

  /// Excited swing/wobble on the hook (running).
  excited,

  /// Drooping to one side (error consolation).
  droop,

  /// Upright with a proud tilt (success).
  proud,
}

/// Which localized tip to show (`aiImport.clippy.*` ARB keys).
enum ClippyTipKey {
  noConfig,
  running,
  error,
  success,

  /// Idle jokes — a small fixed set from the Clippy canon
  /// (`aiImport.clippy.idle1..3`).
  idle1,
  idle2,
  idle3,
}

final class ClippyTip {
  const ClippyTip(this.key, this.pose);

  final ClippyTipKey key;
  final ClippyPose pose;
}

/// Pure trigger mapping (Decision D4). [triggerCount] is the number of
/// tips already shown in this overlay session — it cycles the idle
/// jokes deterministically (never randomly).
ClippyTip clippyTipFor(ClippyFlowState state, {required int triggerCount}) {
  return switch (state) {
    ClippyFlowState.noConfig => const ClippyTip(
      ClippyTipKey.noConfig,
      ClippyPose.neutral,
    ),
    ClippyFlowState.running => const ClippyTip(
      ClippyTipKey.running,
      ClippyPose.excited,
    ),
    ClippyFlowState.error => const ClippyTip(
      ClippyTipKey.error,
      ClippyPose.droop,
    ),
    ClippyFlowState.success => const ClippyTip(
      ClippyTipKey.success,
      ClippyPose.proud,
    ),
    ClippyFlowState.idle => ClippyTip(
      // Deterministic rotation over the fixed idle set.
      ClippyTipKey.values[ClippyTipKey.idle1.index + (triggerCount % 3)],
      ClippyPose.neutral,
    ),
  };
}
