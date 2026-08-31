// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash (opencode-go)

import 'app.dart';
import 'app_config.dart';

/// Production entrypoint: `flutter run -t lib/main_prod.dart --flavor prod`
/// (or `flutter build apk -t lib/main_prod.dart --flavor prod`). The prod
/// startup guards in [bootstrap] reject dev-auth flags and a missing pinned
/// prod CA fail-closed.
Future<void> main() => bootstrap(Flavor.prod);
