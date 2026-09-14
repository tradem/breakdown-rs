<!-- SPDX-License-Identifier: AGPL-3.0 -->
<!-- Copyright (C) 2024-2026 Breakdown RS Contributors -->
<!-- Co-authored-by: omen-alpha (opencode-go) -->

# frontend_flutter

The Android-first Flutter client of [breakdown-rs](https://github.com/tradem/breakdown-rs)
— a collaborative costume and scene continuity breakdown app with a
CQRS / event-sourced Rust backend.

## Documentation

- [Hosting your own instance](docs/self-hosting.md) — deploy your own
  backend and build an instance-owned Android APK from source (the
  officially published APK is deliberately bound to the project backend).
- [Android release process](docs/release-process.md) — the project's
  tag → GitHub-Release pipeline (maintainers).
- [Release signing key custody](docs/release-signing-key-custody.md) —
  keystore custody and fingerprint contract (maintainers).

## Development

See the monorepo root [README](../README.md) for the backend dev runtime
(Postgres + SierraDB + API on `:3000`, optional Logto IdP overlay), and
[`AGENTS.md`](AGENTS.md) for the app's architecture and coding
conventions.

```bash
flutter run --flavor dev --dart-define=API_BASE=http://10.0.2.2:3000
```

## License

GNU AGPL-3.0 — see the monorepo [LICENSE](../LICENSE).
