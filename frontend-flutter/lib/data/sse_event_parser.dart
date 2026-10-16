// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: glm-5.3-flash-flex (neuralwatt)

/// One parsed Server-Sent-Events frame (issue #664, ADR-038 D6).
class SseEvent {
  const SseEvent({this.id, required this.event, required this.data});

  /// The frame's `id:` field (the server watermark) — `null` when absent.
  final String? id;

  /// The frame's `event:` field (empty-string default per the SSE spec).
  final String event;

  /// The frame's `data:` payload, multi-line data joined with `\n`.
  final String data;
}

/// Pure line-based SSE frame parser (issue #664, ADR-038 D6).
///
/// Feed it the decoded UTF-8 lines of the response stream (via
/// `LineSplitter`); it emits one [SseEvent] per completed frame. Semantics
/// follow the WHATWG `text/event-stream` spec to the extent the backend
/// contract uses it:
///
/// * `: comment` lines (the backend's `: keep-alive`) are ignored;
/// * `id`/`event`/`data` fields accumulate until the blank line closes
///   the frame; multi-line `data` joins with `\n`;
/// * a frame with no `data` payload is not emitted (e.g. a bare keep-alive
///   comment followed by a blank line).
///
/// Pure and side-effect free apart from its own accumulation state, so it
/// is unit-testable without a socket.
class SseEventParser {
  final List<String> _dataLines = <String>[];
  String? _id;
  String? _event;

  /// Feed one line (without its line terminator). Returns the completed
  /// [SseEvent] when the line closes a frame, otherwise `null`.
  SseEvent? addLine(String line) {
    // The frame terminator: an empty (or CR-only, already split away) line.
    if (line.isEmpty) {
      return _flush();
    }
    // Comment / keep-alive (`: keep-alive`) — never part of a frame.
    if (line.startsWith(':')) {
      return null;
    }
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    // Exactly one leading space after the colon is stripped per spec.
    if (value.startsWith(' ')) {
      value = value.substring(1);
    }
    switch (field) {
      case 'id':
        _id = value;
      case 'event':
        _event = value;
      case 'data':
        _dataLines.add(value);
      default:
        // Unknown field (e.g. `retry:`) — tolerated and ignored, per spec.
        break;
    }
    return null;
  }

  SseEvent? _flush() {
    // A frame with no `data` payload (e.g. a bare `id:` line) is not a
    // deliverable event — the backend contract always carries a JSON body.
    // All accumulated field state resets either way.
    if (_dataLines.isEmpty) {
      _id = null;
      _event = null;
      return null;
    }
    final event = SseEvent(
      id: _id,
      event: _event ?? '',
      data: _dataLines.join('\n'),
    );
    _dataLines.clear();
    _id = null;
    _event = null;
    return event;
  }
}
