// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

/// Midpoint order-key derivation for single-position reorders
/// (`flutter-costume-domains` 6.1).
///
/// Keys live over the fixed printable-ASCII alphabet `!`..`~` (bytes
/// `33..=126`), matching the SQL `ORDER BY order_key ASC` semantics of the
/// read model and the backend `LexicalSortKey` contract. Moving a row
/// between two neighbors needs a key strictly inside the pair — an
/// append-after rule (correct for creates) would duplicate or skip keys.
///
/// Returns `null` when no valid key exists between the pair: the only such
/// case is a `lo` that is a strict prefix of `hi` with `hi` continuing at
/// the alphabet floor (`'a'` vs `'a!'`) — nothing over the alphabet fits
/// strictly inside. Callers treat `null` as "cannot reorder here" (no
/// command is issued; a duplicate key would corrupt the total order).
/// Server-generated midpoint keys carry fractional room in practice, so
/// `null` is unreachable outside dense hand-built floors.
String? midpointKey(String lo, String hi) {
  if (lo.compareTo(hi) >= 0) return null;
  final a = lo.codeUnits;
  final b = hi.codeUnits;
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  final prefix = lo.substring(0, i);
  // First differing digit: a missing `lo` digit acts as below-alphabet
  // (-1); `hi` always has a digit here (else `lo >= hi`).
  final x = i < a.length ? a[i] : -1;
  final y = b[i];
  if (x >= 0x21) {
    if (y - x > 1) {
      // Room inside the pair: emit the midpoint digit and finish (any tail
      // keeps the order: prefix is already strictly inside on this digit).
      return '$prefix${String.fromCharCode((x + y) ~/ 2)}';
    }
    // Adjacent real digits (`y == x + 1`): emit `x`, then the smallest tail
    // strictly greater than `lo`'s rest (the pair already differs here, so
    // any tail stays below `hi`).
    final rest = String.fromCharCodes(a.sublist(i + 1));
    return '$prefix${String.fromCharCode(x)}$rest!';
  }
  // `lo` exhausted here: any alphabet digit keeps the result above `lo`
  // (longer with a common prefix). Take the midpoint below `y` when one
  // exists; `y == 0x21` (`'a'` vs `'a!'`) leaves no room → null.
  if (y == 0x21) return null;
  return '$prefix${String.fromCharCode((0x21 + y) ~/ 2)}';
}
