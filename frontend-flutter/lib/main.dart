// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'app.dart';
import 'app_config.dart';

/// Default entrypoint — `dev` flavor (local backend). Use `flutter run -t
/// lib/main_prod.dart --flavor prod` for production builds.
void main() => bootstrap(Flavor.dev);
