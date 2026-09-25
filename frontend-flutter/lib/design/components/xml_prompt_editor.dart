// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: space-bunny-free (opencode-go)

import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/xml.dart';

/// An editable, XML-highlighted prompt field.
///
/// Highlighting is presentation-only: [onChanged] receives the exact source
/// text from the editor controller, never rendered spans. Colors come from the
/// active Material 3 [ColorScheme], so the same component works in light and
/// dark mode without feature-local color literals.
class XmlPromptEditor extends StatefulWidget {
  const XmlPromptEditor({
    super.key,
    required this.text,
    required this.label,
    required this.onChanged,
    this.minLines = 4,
    this.maxLines = 10,
  });

  final String text;
  final String label;
  final ValueChanged<String> onChanged;
  final int minLines;
  final int maxLines;

  @override
  State<XmlPromptEditor> createState() => _XmlPromptEditorState();
}

class _XmlPromptEditorState extends State<XmlPromptEditor> {
  late final CodeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = CodeController(text: widget.text, language: xml);
    // XML prompt completion is not useful here and the overlay can obscure
    // neighboring form fields on a phone.
    _controller.popupController.enabled = false;
  }

  @override
  void didUpdateWidget(XmlPromptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text || _controller.fullText == widget.text) {
      return;
    }
    // Only externally delivered values (for example, prompt defaults arriving
    // after discovery) are reseeded. User typing is already reflected in the
    // provider state, so it takes this branch neither a caret reset nor IME
    // disruption.
    final previousOffset = _controller.selection.extentOffset;
    final offset = previousOffset > widget.text.length
        ? widget.text.length
        : previousOffset;
    _controller.value = TextEditingValue(
      text: widget.text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  CodeThemeData _theme(ColorScheme scheme) {
    final base = Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: scheme.onSurface, fontFamily: 'monospace');
    return CodeThemeData(
      styles: {
        'root': base,
        'comment': base.copyWith(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
        'quote': base.copyWith(color: scheme.secondary),
        'keyword': base.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
        ),
        'selector-tag': base.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
        ),
        'subst': base,
        'number': base.copyWith(color: scheme.tertiary),
        'literal': base.copyWith(color: scheme.tertiary),
        'variable': base.copyWith(color: scheme.tertiary),
        'template-variable': base.copyWith(color: scheme.tertiary),
        'string': base.copyWith(color: scheme.secondary),
        'doctag': base.copyWith(color: scheme.secondary),
        'title': base.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
        ),
        'section': base.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
        ),
        'selector-id': base.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.bold,
        ),
        'type': base.copyWith(
          color: scheme.secondary,
          fontWeight: FontWeight.bold,
        ),
        'tag': base.copyWith(color: scheme.primary),
        'name': base.copyWith(color: scheme.primary),
        'attribute': base.copyWith(color: scheme.secondary),
        'regexp': base.copyWith(color: scheme.tertiary),
        'link': base.copyWith(color: scheme.tertiary),
        'symbol': base.copyWith(color: scheme.tertiary),
        'bullet': base.copyWith(color: scheme.tertiary),
        'built_in': base.copyWith(color: scheme.tertiary),
        'builtin-name': base.copyWith(color: scheme.tertiary),
        'meta': base.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CodeTheme(
      data: _theme(scheme),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        child: CodeField(
          controller: _controller,
          minLines: widget.minLines,
          maxLines: widget.maxLines,
          wrap: true,
          gutterStyle: GutterStyle.none,
          cursorColor: scheme.primary,
          background: scheme.surfaceContainerLow,
          textStyle: Theme.of(context).textTheme.bodyMedium!
              .copyWith(color: scheme.onSurface, fontFamily: 'monospace'),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
