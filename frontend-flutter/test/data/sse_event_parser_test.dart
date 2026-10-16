// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3 (neuralwatt)

// Tier-1 unit tests for the pure SSE line parser (issue #664, ADR-038 D6).

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend_flutter/data/sse_event_parser.dart';

void main() {
  group('SseEventParser', () {
    test('parses a complete event: job frame with id and data', () {
      final parser = SseEventParser();
      final lines = 'event: job\nid: 42\ndata: {"job":{"id":"j1"}}\n\n'.split(
        '\n',
      );
      final events = <SseEvent>[];
      for (final line in lines) {
        final event = parser.addLine(line);
        if (event != null) events.add(event);
      }
      expect(events, hasLength(1));
      expect(events.single.event, 'job');
      expect(events.single.id, '42');
      expect(events.single.data, '{"job":{"id":"j1"}}');
    });

    test('ignores keep-alive comment lines entirely', () {
      final parser = SseEventParser();
      expect(parser.addLine(': keep-alive'), isNull);
      // The bare blank line after a comment is not a frame.
      expect(parser.addLine(''), isNull);
    });

    test('joins multi-line data with newline separators', () {
      final parser = SseEventParser();
      expect(parser.addLine('event: job'), isNull);
      expect(parser.addLine('data: line1'), isNull);
      expect(parser.addLine('data: line2'), isNull);
      final event = parser.addLine('');
      expect(event, isNotNull);
      expect(event!.data, 'line1\nline2');
      expect(event.event, 'job');
    });

    test('a frame without data is not emitted (id-only frame)', () {
      final parser = SseEventParser();
      parser.addLine('id: 7');
      expect(parser.addLine(''), isNull);
    });

    test('tolerates a field without a colon and unknown fields', () {
      final parser = SseEventParser();
      expect(parser.addLine('retry'), isNull);
      expect(parser.addLine('retry: 3000'), isNull);
      expect(parser.addLine('data: x'), isNull);
      final event = parser.addLine('');
      expect(event!.data, 'x');
    });

    test('state resets after a frame — the next frame is independent', () {
      final parser = SseEventParser();
      parser.addLine('event: job');
      parser.addLine('id: 1');
      parser.addLine('data: a');
      expect(parser.addLine('')!.id, '1');
      parser.addLine('event: ping');
      parser.addLine('data: b');
      final second = parser.addLine('');
      expect(second!.id, isNull);
      expect(second.event, 'ping');
      expect(second.data, 'b');
    });

    test('strips exactly one leading space after the colon', () {
      final parser = SseEventParser();
      parser.addLine('data:  two spaces kept');
      expect(parser.addLine('')!.data, ' two spaces kept');
    });
  });
}
