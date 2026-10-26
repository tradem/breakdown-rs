// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'package:flutter/material.dart';

import '../../design/gen/design_tokens.g.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../src/health/backend_health_providers.dart';

/// Shared presentation vocabulary of the backend health surfaces — the
/// drawer pill (#657) and its detail sheet (#730).
///
/// One source for "which icon, which color, which localized label" so the
/// two surfaces can never tell different stories about the same tier, and
/// so **color is never the sole carrier of meaning** (glossary rule): every
/// mapping pairs the DTCG semantic status color with a Material Symbol AND
/// a localized label.
///
/// Colors ride the DTCG semantic tokens (`colorSemanticSuccess*` /
/// `Warning*` / `Error*`), light variant on light surfaces and dark variant
/// on dark surfaces — they are accent colors designed per brightness (see
/// `design/tokens/color.json`). M3 has no `successContainer` /
/// `warningContainer` roles.
({IconData icon, String label, Color color}) backendHealthTierPresentation(
  BackendHealthTier tier, {
  required AppLocalizations l10n,
  required bool isLight,
}) => switch (tier) {
  BackendHealthTier.healthy => (
    icon: Icons.check_circle,
    label: l10n.healthPillHealthy,
    color: isLight
        ? DesignTokens.colorSemanticSuccessLight
        : DesignTokens.colorSemanticSuccessDark,
  ),
  BackendHealthTier.degraded => (
    icon: Icons.warning_amber_rounded,
    label: l10n.healthPillDegraded,
    color: isLight
        ? DesignTokens.colorSemanticWarningLight
        : DesignTokens.colorSemanticWarningDark,
  ),
  // The two red tiers (unhealthy/offline) share the error token with the
  // #654 offline pill; only the localized label and icon differ.
  BackendHealthTier.unhealthy => (
    icon: Icons.report,
    label: l10n.healthPillUnhealthy,
    color: isLight
        ? DesignTokens.colorSemanticErrorLight
        : DesignTokens.colorSemanticErrorDark,
  ),
  BackendHealthTier.offline => (
    icon: Icons.cloud_off,
    label: l10n.healthPillOffline,
    color: isLight
        ? DesignTokens.colorSemanticErrorLight
        : DesignTokens.colorSemanticErrorDark,
  ),
};

/// Localized, **topology-free** label of one dependency check (issue #730).
///
/// The backend's check keys name internal components (`postgres`,
/// `sierradb`, `vault`, `garage`); the user-facing label says what the
/// dependency is FOR instead of leaking deployment internals (the backend
/// already sanitizes its own `description` to static text — we do not render
/// server sentences at all, localized copy only, AGENTS.md §5/§9).
///
/// Unknown keys (a future backend check, e.g. a new storage backend) fall
/// back to a generic label rather than printing the raw key, so no
/// diagnostic path renders an internal identifier.
String backendHealthCheckLabel(AppLocalizations l10n, String checkName) =>
    switch (checkName) {
      'postgres' => l10n.healthCheckDatabase,
      'sierradb' => l10n.healthCheckEventStore,
      'vault' => l10n.healthCheckSecrets,
      'garage' => l10n.healthCheckAiStorage,
      _ => l10n.healthCheckOther,
    };

/// Localized status word of one dependency check (issue #730).
String backendHealthCheckStatusLabel(
  AppLocalizations l10n,
  BackendHealthCheckStatus status,
) => switch (status) {
  BackendHealthCheckStatus.healthy => l10n.healthCheckStatusHealthy,
  BackendHealthCheckStatus.degraded => l10n.healthCheckStatusDegraded,
  BackendHealthCheckStatus.unhealthy => l10n.healthCheckStatusUnhealthy,
};

/// Icon + semantic color of one dependency check's status (issue #730).
/// Mirrors [backendHealthTierPresentation] so an `Unhealthy` dependency and
/// an `Unhealthy` aggregate report read the same way.
({IconData icon, Color color}) backendHealthCheckPresentation(
  BackendHealthCheckStatus status, {
  required bool isLight,
}) => switch (status) {
  BackendHealthCheckStatus.healthy => (
    icon: Icons.check_circle,
    color: isLight
        ? DesignTokens.colorSemanticSuccessLight
        : DesignTokens.colorSemanticSuccessDark,
  ),
  BackendHealthCheckStatus.degraded => (
    icon: Icons.warning_amber_rounded,
    color: isLight
        ? DesignTokens.colorSemanticWarningLight
        : DesignTokens.colorSemanticWarningDark,
  ),
  BackendHealthCheckStatus.unhealthy => (
    icon: Icons.report,
    color: isLight
        ? DesignTokens.colorSemanticErrorLight
        : DesignTokens.colorSemanticErrorDark,
  ),
};
