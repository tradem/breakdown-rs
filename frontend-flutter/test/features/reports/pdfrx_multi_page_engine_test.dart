// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: deepseek-v4.1-flash (opencode-go)

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Host-side guard for the one dependency behind the in-app report preview
/// (`ReportPreviewScreen`, `lib/features/reports/reports_screen.dart`).
///
/// Issue #976 moved `pdfrx` 2.13.1 -> 3.1.0. The viewer widget itself is
/// covered by `reports_screen_test.dart` (pumping `ReportPreviewScreen` only
/// proves the widget tree builds — in a widget test the engine is stubbed out),
/// and the on-device flow by `integration_test/reports_smoke_test.dart`. Neither
/// answers the question the major bump raises: *does the new engine still open
/// a multi-page PDF, rasterize a page and extract its text?*
///
/// So this test drives the real pdfium engine headlessly through the same
/// `pdfrx` API the preview widget is built on: generate a deterministic
/// three-page PDF in a temp dir, open it, render page 1 to pixels and read the
/// text of every page. No device, no emulator, no network, no fixture binary.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'pdfrx opens, rasterizes and reads text from a multi-page PDF',
    () async {
      final dir = await Directory.systemTemp.createTemp('pdfrx_engine_test');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/schedule.pdf');
      await file.writeAsBytes(buildMultiPagePdf(pageCount: 3));

      final document = await PdfDocument.openFile(file.path);
      addTearDown(document.dispose);

      expect(document.pages, hasLength(3));

      final first = document.pages.first;
      final image = await first.render(
        fullWidth: first.width * 2,
        fullHeight: first.height * 2,
      );
      expect(image, isNotNull, reason: 'pdfium must rasterize page 1');
      expect(image!.width, greaterThan(0));
      expect(image.height, greaterThan(0));
      expect(image.pixels, hasLength(image.width * image.height * 4));

      // Text extraction proves it is the *same* document across pages, not one
      // rendered page 1 three times.
      for (final (index, page) in document.pages.indexed) {
        final text = await page.loadText();
        expect(
          text?.fullText,
          contains('Schedule page ${index + 1}'),
          reason: 'page ${index + 1} text must be readable',
        );
      }
    },
  );
}

/// Emits a minimal but complete PDF 1.4 with one Helvetica text line per page.
///
/// Hand-built (offsets, xref and trailer included) so the guard has no fixture
/// binary in the tree and no PDF authoring package in `pubspec.yaml`.
Uint8List buildMultiPagePdf({required int pageCount}) {
  final objects = <String>[];
  final kids = List.generate(pageCount, (i) => '${3 + 2 * i} 0 R').join(' ');
  final fontId = 3 + 2 * pageCount;

  objects.add('<< /Type /Catalog /Pages 2 0 R >>');
  objects.add('<< /Type /Pages /Kids [$kids] /Count $pageCount >>');
  for (var i = 0; i < pageCount; i++) {
    final content = 'BT /F1 24 Tf 72 700 Td (Schedule page ${i + 1}) Tj ET';
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 $fontId 0 R >> >> '
      '/Contents ${4 + 2 * i} 0 R >>',
    );
    objects.add('<< /Length ${content.length} >>\nstream\n$content\nendstream');
  }
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xrefOffset = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xrefOffset\n%%EOF\n',
  );

  return Uint8List.fromList(out.toString().codeUnits);
}
