// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'app.dart';
import 'app_config.dart';

/// Production entrypoint — `prod` flavor (deployed edge, pinned prod CA set).
/// Dev-auth mode is unreachable here (see [AppConfig.devAuthMode]).
void main() => bootstrap(Flavor.prod);
