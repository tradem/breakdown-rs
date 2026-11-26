// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

// Tier-2 widget tests for the shell's bottom-inset seam (issue #991 review):
// a scrollable that passes its OWN `padding` opts out of Flutter's automatic
// `MediaQuery` inset consumption, so the seam has to add it exactly once.

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/design/scroll_insets.dart';

void main() {
  testWidgets('adds the ambient bottom inset once, to the bottom only', (
    tester,
  ) async {
    // 96 dp is the shell's derived reservation (the bar's laid-out height plus
    // the plus action's band where it renders) — never a literal this seam
    // knows about.
    const MediaQueryData ambient = MediaQueryData(
      padding: EdgeInsets.only(top: 24, bottom: 96),
    );
    late EdgeInsets inset;
    await tester.pumpWidget(
      MediaQuery(
        data: ambient,
        child: Builder(
          builder: (context) {
            inset = withBottomInset(
              context,
              const EdgeInsets.fromLTRB(4, 8, 12, 16),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // The widget's own padding survives; the inset lands on the bottom edge
    // exactly once (top/left/right untouched, no doubling of the 16).
    expect(inset, const EdgeInsets.fromLTRB(4, 8, 12, 112));
  });

  testWidgets('outside the shell the padding is unchanged', (tester) async {
    late EdgeInsets inset;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          inset = withBottomInset(context, const EdgeInsets.all(16));
          return const SizedBox.shrink();
        },
      ),
    );
    // No ambient inset (a test surface has zero padding): a screen that is not
    // inside the compact shell composites over 0 and must not lose its own
    // padding to the seam.
    expect(inset, const EdgeInsets.all(16));
  });
}
