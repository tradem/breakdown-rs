## Summary

Implements the `wire-openapi-dart-client` OpenSpec change (AGENTS.md §3,
decision D1/D8) and its direct CI follow-ups. Lands the generated typed Dart
client, per-flavor CA pinning, the data/-layer repositories, and the two
remaining deferred CI gates (drift check + coverage).

- **Generated client** (`vendor/breakdown_api/`, package `breakdown_api`): Dio-based
  (`dart-dio` generator, built_value serialization), regenerated from
  `backend/openapi.yaml` via `scripts/regen-client.sh`. The script is
  caller-CWD-independent, pins the generator version from `openapitools.json`,
  strips timestamps, injects a `// GENERATED` banner, runs build_runner, and
  drops standalone-package cruft. Consumed as a path dependency; imported via
  `package:breakdown_api/breakdown_api.dart`.
- **CA pinning** (`lib/src/network/api_client.dart`, issue #301): buildApiClient
  now builds a SecurityContext(withTrustedRoots: false) that trusts only the
  per-flavor CA bundle (assets/certs/{dev,prod}/ca.pem), attached via
  IOHttpClientAdapter. A system-trusted but unpinned cert is rejected. Bundles
  are flavor-selected at build time; prod is a placeholder to be replaced with
  the real edge CA. Regression test (test/network/cert_pinning_test.dart)
  proves the rejection path with a real local TLS handshake.
- **data/ layer** (lib/core/, lib/data/): ProblemError + RFC 9457 parsing
  (problemErrorFromDio, branching on stable code), Result<T> (fpdart Either),
  BaseRepository with a run helper mapping DioException ->
  Left(ProblemError), and one repository per aggregate boundary (seasons,
  costumes, scenes, shooting_days, scene_shoots, characters, costume_categories,
  photos). Each returns Result — never raw HTTP types, never throws.
- **CI gates** (.github/workflows/flutter-ci.yml): the OpenAPI-client drift
  job (regenerate into a throwaway, diff against committed, fail on difference;
  backend/openapi.yaml added to path filters) and the coverage job
  (flutter test --coverage + coverde check 60). Both were deferred; both are
  now wired. Foundation unit test (test/unit/problem_error_test.dart, 6 cases)
  covers the pure parsing logic.

## Verification

- flutter analyze clean (exit 0) on both the parent and the generated package.
- Full suite 9/9 passing (6 unit + 2 cert-pinning + 1 widget).
- coverde global coverage 75% (33/44), passes the 60% threshold.
- Committed tree is byte-identical to scripts/regen-client.sh output
  (excluding the gitignored .dart_tool), satisfying the CI drift check.

## Notes

- openapi-generator 7.25.0 is the latest release; its generated source_gen
  constraint resolves to 3.1.0, incompatible with the Dart 3.13.x analyzer API
  (getInvocation undefined). scripts/regen-client.sh injects
  dependency_overrides: source_gen: 3.0.0. Revisit if the generator is upgraded.
- Co-author attribution on previously-edited scaffold files corrected to
  hy3 (opencode-go); new files carry longcat-2.0 (opencode-go).

Co-authored-by: longcat-2.0 (opencode-go)
