#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: longcat-2.0 (opencode-go)
set -euo pipefail
flutter test --coverage 2>&1 | tail -20
echo "--- lcov summary ---"
if command -v coverde >/dev/null 2>&1; then
  coverde check 2>&1 | tail -10
else
  echo "coverde not installed; showing raw lcov line coverage"
  dart pub global list 2>/dev/null | grep coverde
fi
