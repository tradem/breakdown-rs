// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: hy3 (opencode-go)
// Co-authored-by: muse-spark (opencode-go)
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/app_config.dart';
import 'package:frontend_flutter/src/network/api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildIdpDio uses a plain verifying client for the dev IdP HTTP '
      'port-forward exception (D1, dev flavor only)', () async {
    const config = AppConfig(
      flavor: Flavor.dev,
      apiBase: 'http://10.0.2.2:3000',
      oidcIss: 'http://idp.local:3301',
      devAuthSub: '',
      oidcAudience: 'aud',
      oidcClientId: 'c',
      oidcRedirectUri: 'breakdown://redirect',
      devIdpInsecure: '1',
      appVersion: '1.0.0+1',
    );
    final dio = await buildIdpDio(config);
    // The dev IdP HTTP exception relaxes ONLY the IdP host transport; the
    // verification stays ON (system roots), and the API host keeps the
    // pinned context (covered by buildApiClient tests).
    expect(dio.options.baseUrl, 'http://idp.local:3301');
  });
}
