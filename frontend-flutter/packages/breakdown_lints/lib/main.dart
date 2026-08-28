// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'rules/discard_result.dart';
import 'rules/no_hardcoded_secrets.dart';
import 'rules/no_insecure_tls.dart';
import 'rules/no_throw_in_data_domain.dart';

/// Top-level plugin entrypoint loaded by the analysis server when
/// `breakdown_lints` is listed under `analyzer > plugins` in analysis_options.
final plugin = BreakdownLints();

class BreakdownLints extends Plugin {
  @override
  String get name => 'breakdown_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(DiscardResultRule())
      ..registerWarningRule(NoThrowInDataDomainRule())
      ..registerWarningRule(NoInsecureTlsRule())
      ..registerWarningRule(NoHardcodedSecretsRule());
  }
}
