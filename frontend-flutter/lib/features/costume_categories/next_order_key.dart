// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

/// Client-side append order-key derivation for costume categories
/// (`flutter-hierarchy-navigation` D4, `flutter-costume-categories-screen`).
///
/// `CreateCostumeCategoryRequest` requires `order_key`. The client derives an
/// append-after-last key over the SAME season projection's existing keys —
/// never from a parallel client-side ordering scheme:
///
/// - empty list → `!` (first alphabet position);
/// - otherwise the successor of the greatest key's final byte over the fixed
///   printable-ASCII alphabet `!`..`~` (bytes 33..=126);
/// - last-position overflow grows the key length with a lexically greater
///   successor (`~` → `~!`, never `!!` which sorts *before* `~` and would
///   break append-after-last).
///
/// Every derived key sorts strictly after its predecessor (asserted by unit
/// tests, by value and by comparison). Insertion is append-only, which is
/// order-preserving by construction; the server-side `LexicalSortKey`
/// midpoint semantic is deliberately not replicated and full reordering is
/// a non-goal.
///
/// Callers MUST pass the complete season projection (archived rows included
/// — the archived-visible toggle affects rendering only, never derivation).
String nextOrderKey(Iterable<String> existingKeys) {
  var greatest = '';
  var found = false;
  for (final key in existingKeys) {
    if (!found || key.compareTo(greatest) > 0) {
      greatest = key;
      found = true;
    }
  }
  if (!found) return '!';

  final units = greatest.codeUnits;
  final last = units.last;
  // Overflow of the last alphabet position: grow the length with a
  // lexically greater successor (`~` → `~!`).
  if (last >= 0x7E) return '$greatest!';
  final next = String.fromCharCodes([
    ...units.sublist(0, units.length - 1),
    last + 1,
  ]);
  // Defensive: the successor must sort strictly after its predecessor.
  assert(
    next.compareTo(greatest) > 0,
    'derived order key must sort after its predecessor',
  );
  return next;
}
