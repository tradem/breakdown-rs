// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)
// Co-authored-by: deepseek-v4-flash (neuralwatt)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_flutter/features/seasons/widgets/seasons_empty_state.dart';
import 'package:frontend_flutter/l10n/generated/app_localizations.dart';

Widget _localizedEmptyState(Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SeasonsEmptyState(onImport: () {})),
);

void main() {
  testWidgets('seasons copy follows the German template locale', (
    tester,
  ) async {
    await tester.pumpWidget(_localizedEmptyState(const Locale('de', 'DE')));
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Seasons'), findsOneWidget);
    expect(find.text('Season-Setup starten'), findsOneWidget);
    expect(find.text('KI-Import öffnen'), findsOneWidget);
  });

  testWidgets('seasons copy follows the English locale', (tester) async {
    await tester.pumpWidget(_localizedEmptyState(const Locale('en', 'US')));
    await tester.pumpAndSettle();

    expect(find.text('No seasons yet'), findsOneWidget);
    expect(find.text('Start season setup'), findsOneWidget);
    expect(find.text('Open AI import'), findsOneWidget);
  });
}
