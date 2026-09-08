<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->

# Tasks: 378-active-block-header

- [x] 1. `ActiveBlock` scope provider (`lib/auth/active_block.dart` +
      `active_block.g.dart` via `build_runner`): `ActiveScope`
      (`seasonId`, `blockId`), keepAlive notifier with `set`/`clear`;
      unit test set/clear/initial-null.
- [x] 2. `ActiveBlockInterceptor`
      (`lib/src/network/active_block_interceptor.dart`): attaches
      `X-Active-Block` when non-null, omits when null, never throws;
      unit tests mirroring `auth_token_interceptor_test.dart`
      (attach / omit / empty-ignores / preserves existing headers).
- [x] 3. Dio wiring: `buildPinnedDio(..., {String? activeBlockId})` +
      `apiDioProvider` watches `activeBlockProvider`; bootstrap path
      unchanged (null). Update `api_client` doc comments.
- [x] 4. Implicit set point: `BlocksScreen` tap sets the scope from the
      `BlockView` synchronously before pushing `EpisodesScreen`
      (sole production set point — provider writes during builds throw);
      sign-out + backend-switch clear the scope via `SessionReset`.
- [x] 5. `ActiveBlockGate` resolution helper + picker dialog; integrate
      into `CostumesScreen` and `CharactersScreen` (reuse sticky scope,
      auto-pick single block, remembered picker for multi, hint for zero).
- [x] 6. Tests: provider tests, interceptor tests, gate resolution tests
      (fake `blocksListFetch`), widget test for picker-remember behavior.
- [x] 7. Verify: `dart format --set-exit-if-changed .`,
      `flutter analyze`, `flutter test`, `build_runner` regen committed;
      confirm `vendor/breakdown_api/` untouched.
