// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_providers.dart';
import '../../core/problem_error.dart';
import 'characters_controller.dart';
import 'characters_state.dart';

/// `CharacterDetailScreen` — contact + measurements editors.
///
/// Both editors perform full-replacement PATCH commands with the `version`
/// echoed from the read row, prefilled from the read DTO; 409 surfaces
/// "changed elsewhere — refresh" copy. Empty-string measurement fields
/// remain valid submissions (the contract types them as strings; the client
/// adds no client-side numeric validation it cannot enforce honestly).
class CharacterDetailScreen extends ConsumerWidget {
  const CharacterDetailScreen({
    super.key,
    required this.season,
    required this.characterId,
  });

  final SeasonView season;
  final String characterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(authSessionControllerProvider, (_, session) {
      final signedOut =
          (session is AsyncData && session.value == null) ||
          session is AsyncError;
      if (signedOut && context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final state = ref.watch(charactersControllerProvider(season.id));
    final controller = ref.read(
      charactersControllerProvider(season.id).notifier,
    );
    final character = _resolve(state);

    return Scaffold(
      appBar: AppBar(title: Text(character?.name ?? 'Character')),
      body: switch ((character, state.projected)) {
        // Resolved row: editors render (prefilled from the read DTO).
        (final c?, _) => RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            key: Key('character-detail-$characterId'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (state.commandError case final error?)
                _InlineError(
                  text: characterErrorCopy(error),
                  onDismiss: controller.dismissCommandError,
                ),
              _CategoryRow(character: c),
              const SizedBox(height: 16),
              _ContactSection(season: season, character: c),
              const Divider(height: 32),
              _MeasurementsSection(season: season, character: c),
            ],
          ),
        ),
        // First snapshot still in flight.
        (null, AsyncLoading()) => const Center(
          child: CircularProgressIndicator(key: Key('character-loading')),
        ),
        // Settled with an error and no retained row: retry affordance.
        (null, AsyncError(:final error)) => _DetailErrorView(
          code: error is ProblemError ? error.code : 'unknown',
          onRetry: controller.refresh,
        ),
        // Settled without the row (deleted character): not-found view
        // instead of an endless spinner.
        (null, _) => _DetailNotFoundView(
          onBack: () => Navigator.of(context).pop(),
        ),
      },
    );
  }

  CharacterView? _resolve(CharactersScreenState state) {
    for (final c in state.cachedRows) {
      if (c.id == characterId) return c;
    }
    return null;
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.text, this.onDismiss});

  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const Key('character-detail-error'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.character});

  final CharacterView character;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.person_outline),
      const SizedBox(width: 8),
      Text(
        character.name,
        key: Key('character-detail-name-${character.id}'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(width: 8),
      Chip(
        key: Key('character-category-${character.id}'),
        label: Text(characterCategoryLabel(character)),
      ),
    ],
  );
}

class _ContactSection extends ConsumerStatefulWidget {
  const _ContactSection({required this.season, required this.character});

  final SeasonView season;
  final CharacterView character;

  @override
  ConsumerState<_ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends ConsumerState<_ContactSection> {
  late final TextEditingController _email;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.character.contact.email ?? '');
    _phone = TextEditingController(text: widget.character.contact.phone ?? '');
  }

  @override
  void didUpdateWidget(covariant _ContactSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id ||
        oldWidget.character.version != widget.character.version) {
      _email.text = widget.character.contact.email ?? '';
      _phone.text = widget.character.contact.phone ?? '';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Contact', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      TextField(
        key: Key('character-email-${widget.character.id}'),
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Email',
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        key: Key('character-phone-${widget.character.id}'),
        controller: _phone,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          labelText: 'Phone',
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          key: Key('character-contact-save-${widget.character.id}'),
          onPressed: () => ref
              .read(charactersControllerProvider(widget.season.id).notifier)
              .updateContact(
                character: widget.character,
                email: _email.text.isEmpty ? null : _email.text,
                phone: _phone.text.isEmpty ? null : _phone.text,
              ),
          child: const Text('Save contact'),
        ),
      ),
    ],
  );
}

class _MeasurementsSection extends ConsumerStatefulWidget {
  const _MeasurementsSection({required this.season, required this.character});

  final SeasonView season;
  final CharacterView character;

  @override
  ConsumerState<_MeasurementsSection> createState() =>
      _MeasurementsSectionState();
}

class _MeasurementsSectionState extends ConsumerState<_MeasurementsSection> {
  late final Map<String, TextEditingController> _fields;

  static const _keys = [
    'height',
    'weight',
    'chest',
    'waist',
    'hips',
    'shoeSize',
    'hatSize',
  ];

  String _value(String key) {
    final m = widget.character.measurements;
    return switch (key) {
      'height' => m.height,
      'weight' => m.weight,
      'chest' => m.chest,
      'waist' => m.waist,
      'hips' => m.hips,
      'shoeSize' => m.shoeSize,
      'hatSize' => m.hatSize,
      _ => '',
    };
  }

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final k in _keys) k: TextEditingController(text: _value(k)),
    };
  }

  @override
  void didUpdateWidget(covariant _MeasurementsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.version != widget.character.version) {
      for (final k in _keys) {
        _fields[k]!.text = _value(k);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Measurements', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final k in _keys) ...[
        TextField(
          key: Key('character-measure-$k-${widget.character.id}'),
          controller: _fields[k],
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: k,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          key: Key('character-measurements-save-${widget.character.id}'),
          onPressed: () => ref
              .read(charactersControllerProvider(widget.season.id).notifier)
              .updateMeasurements(
                character: widget.character,
                measurements: CharacterMeasurements(
                  (b) => b
                    ..height = _fields['height']!.text
                    ..weight = _fields['weight']!.text
                    ..chest = _fields['chest']!.text
                    ..waist = _fields['waist']!.text
                    ..hips = _fields['hips']!.text
                    ..shoeSize = _fields['shoeSize']!.text
                    ..hatSize = _fields['hatSize']!.text,
                ),
              ),
          child: const Text('Save measurements'),
        ),
      ),
    ],
  );
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({required this.code, this.onRetry});

  final String code;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Could not load the character ($code).',
          key: const Key('character-detail-error'),
        ),
        const SizedBox(height: 8),
        FilledButton.tonal(
          key: const Key('character-detail-retry'),
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _DetailNotFoundView extends StatelessWidget {
  const _DetailNotFoundView({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This character no longer exists.',
          key: Key('character-detail-gone'),
        ),
        if (onBack != null)
          FilledButton.tonal(onPressed: onBack, child: const Text('Back')),
      ],
    ),
  );
}
