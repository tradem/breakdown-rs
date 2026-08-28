# breakdown_lints_runner

Custom lint runner for the `breakdown_lints` rules.

## Why

The `breakdown_lints` analyzer plugin uses `analysis_server_plugin`, which only
loads inside the analysis server (IDE/LSP mode) — not in the batch
`dart analyze` / `flutter analyze` CLI. This runner re-implements the same four
rules using the `analyzer` package directly, so they can be enforced in CI
without the plugin system. See issue #299.

## Rules

| Code | Default Severity | Description |
|---|---|---|
| `discard_result` | ERROR | Flags un-awaited `Future` or discarded `Result`/`Either` |
| `no_throw_in_data_domain` | ERROR | Forbids `throw` in `lib/data/**` and `lib/domain/**` |
| `no_insecure_tls` | ERROR | Forbids disabling TLS certificate verification |
| `no_hardcoded_secrets` | WARNING | Heuristic detection of hardcoded secrets |

## Usage

```bash
cd tool/breakdown_lints_runner
dart pub get
dart run bin/run_lints.dart ../..
```

The argument is the Flutter project root (defaults to `../../` relative to
the tool package, i.e. the `frontend-flutter/` directory). The runner
analyzes all non-generated `lib/**/*.dart` files (excluding
`lib/api/generated/`).

Exits 0 if no violations found, non-zero otherwise.
