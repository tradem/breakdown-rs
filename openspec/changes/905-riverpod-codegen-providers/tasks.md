<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: deepseek-v4.1-flash (opencode-go) -->

# Tasks — Riverpod codegen provider migration (issue #905)

## 1. Shared overlay base

- [x] 1.1 `lib/domain/reconciliation/overlay_store.dart`: `OverlayStore`
      becomes `mixin OverlayStore<E extends ReconciliationOverlay> on
      AnyNotifier<List<E>, List<E>>` — the behaviour-carrying methods
      (`add`, `markAllReconciling`, `dropProjectedRows`, `markAllStale`) are
      unchanged; the `build() => const []` default moves to the subclass.
- [x] 1.2 `SeasonOverlays` becomes
      `@Riverpod(keepAlive: true) class SeasonOverlays extends _$SeasonOverlays
      with OverlayStore<SeasonOverlay>` and declares its own `build()`.

## 2. Providers named by the issue (`features/ai_import/import_jobs/import_submit_controller.dart`)

- [x] 2.1 `pendingDocumentProvider`: `PendingDocument` → codegen.
- [x] 2.2 `aiStampWarningProvider`: `_StampWarning` → public `AiStampWarning`
      (the generated name must stay `aiStampWarningProvider`).
- [x] 2.3 `pendingEpisodeProvider`: `PendingEpisode` → codegen.

## 3. Remaining plain `Notifier` providers (12 total, all `keepAlive: true`)

- [x] 3.1 `cacheGenerationProvider` (`data/cache/cache_generation.dart`) — adds
      a `part` directive + the annotation import.
- [x] 3.2 `seasonsPrevRowsProvider` (`data/cache/seasons_cache_providers.dart`)
      — `_SeasonsPrevRows` → public `SeasonsPrevRows`.
- [x] 3.3 `runtimeApiBaseProvider` (`data/settings/api_base_override_store.dart`).
- [x] 3.4 `seasonCommandErrorProvider` (`features/seasons/seasons_controller.dart`).
- [x] 3.5 `sessionResetProvider` (`features/auth/sign_out.dart`, `Notifier<void>`).
- [x] 3.6 `signInErrorProvider` + `signInInFlightProvider`
      (`features/auth/login_screen.dart`) — the in-flight provider's
      "auto-disposing" comment is corrected to the keep-alive lifetime it
      actually has (behaviour preserved, not re-decided).
- [x] 3.7 `aiConfigDraftsProvider`
      (`features/ai_import/ai_config/ai_config_controller.dart`).
- [x] 3.8 `seasonMembershipCacheProvider` (`auth/season_membership_provider.dart`).
- [x] 3.9 Every migrated provider states `@Riverpod(keepAlive: true)` and keeps
      its existing name, class name (or the documented rename that preserves
      it) and public methods.

## 4. Documented exception

- [x] 4.1 `easterEggProvider` (`data/settings/easter_eggs_store.dart`) stays
      hand-written: `NotifierProvider.family` with a constructor-injected id
      plus the `HydratedEasterEggs` `overrideWith` bootstrap seed. Recorded in
      the proposal and in the provider-guidance note, so it is not re-litigated
      and not copied.

## 5. Verification

- [x] 5.1 `dart run build_runner build` regenerates the affected `.g.dart`
      files; the diff is committed (never hand-edited).
- [x] 5.2 `dart format --set-exit-if-changed .` clean.
- [x] 5.3 `flutter analyze` clean.
- [x] 5.4 `flutter test` green — the existing suites are the acceptance gate
      for the migrated bodies (no provider contract changed).
- [x] 5.5 `scripts/add-spdx-headers.sh --check` clean for the touched files.
