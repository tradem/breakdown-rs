// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

/// AOT regression probe for [dart-lang/sdk#64917] — NOT application code.
///
/// Dart 3.14.0 broke the AOT register allocator for one specific shape: a
/// `final` local declared without an initializer, assigned inside a pattern
/// `switch` case (with another case exiting early), and then captured by a
/// closure. The JIT runs it fine; `gen_snapshot` aborts with
///
///     runtime/vm/compiler/backend/linearscan.cc: 3013: error: unreachable code
///
/// (the `UNREACHABLE()` in `FlowGraphAllocator::FindCover`), exit -6. That is
/// what killed the v0.4.0 release build on all three ABIs while every JIT
/// gate stayed green — which is why the release pipeline no longer floats on
/// `channel: stable` and `flutter-version` is pinned in
/// `.github/workflows/flutter-ci.yml` and `flutter-release.yml`.
///
/// This file exists so that class of failure is caught by a PR gate instead of
/// a release pipeline: `scripts/release/check-flutter-aot-regression.sh`
/// compiles it with `dart compile aot-snapshot` (same `gen_snapshot` a release
/// build uses, seconds instead of a Gradle build), and the
/// `format-and-analyze` job of `.github/workflows/flutter-ci.yml` runs that
/// against the pinned SDK. Run it by hand before bumping the pin; a
/// reintroduced regression then fails the PR that bumps.
///
/// Do not "clean up" the shape below and do not delete the closure: every
/// element is load-bearing for the repro (drop the capture, the deferred
/// `final`, the early `return`, or the single call site and the crash goes
/// away). See the upstream issue for the full reduction.
///
/// [dart-lang/sdk#64917]: https://github.com/dart-lang/sdk/issues/64917
library;

sealed class Outcome {
  const Outcome();
}

final class Started extends Outcome {
  const Started(this.runId);

  final int runId;
}

final class Refused extends Outcome {
  const Refused();
}

int? _committed;

@pragma('vm:never-inline')
void _apply(void Function() update) => update();

int run(Outcome outcome) {
  final int runId;
  switch (outcome) {
    case Started():
      runId = outcome.runId;
    case Refused():
      return 0;
  }
  _apply(() => _committed = runId);
  return runId;
}

void main(List<String> args) {
  run(args.isEmpty ? const Refused() : const Started(1));
  assert(_committed != null);
}
