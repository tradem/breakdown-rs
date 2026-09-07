// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: muse-spark-1.3-contributor (opencode-go)

import 'package:breakdown_api/breakdown_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/problem_error.dart';
import '../../domain/reconciliation/overlay_store.dart';

export '../../domain/reconciliation/overlay_store.dart' show OverlayStatus;

/// Controller-state optimistic overlay for a create-character command:
/// ephemeral UI state keyed by the server-assigned `id` — never in Drift.
class CharacterOverlay implements ReconciliationOverlay {
  const CharacterOverlay({
    required this.id,
    required this.status,
    this.name,
    this.category,
    this.warning,
  });

  @override
  final String id;

  final String? name;

  /// Category wire string carried from the submitted form (display-only).
  final String? category;

  @override
  final OverlayStatus status;

  @override
  final String? warning;

  @override
  CharacterOverlay copyWithStatus({
    OverlayStatus? status,
    String? warning,
    bool clearWarning = false,
  }) => CharacterOverlay(
    id: id,
    name: name,
    category: category,
    status: status ?? this.status,
    warning: clearWarning ? null : (warning ?? this.warning),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharacterOverlay &&
          other.id == id &&
          other.name == name &&
          other.category == category &&
          other.status == status &&
          other.warning == warning;

  @override
  int get hashCode => Object.hash(id, name, category, status, warning);
}

/// One row rendered by `CharactersScreen`.
sealed class CharacterRow {
  const CharacterRow();
}

class ProjectedCharacterRow extends CharacterRow {
  const ProjectedCharacterRow(this.character);

  /// The generated read DTO (`breakdown_api` `CharacterView`); authoritative,
  /// comes from Drift only.
  final CharacterView character;
}

class OptimisticCharacterRow extends CharacterRow {
  const OptimisticCharacterRow(this.overlay);

  final CharacterOverlay overlay;
}

/// Controller state shape (seasons reference pattern).
class CharactersScreenState {
  const CharactersScreenState({
    required this.projected,
    this.cachedRows = const [],
    this.isStale = false,
    this.overlays = const [],
    this.commandError,
  });

  final AsyncValue<List<CharacterView>> projected;

  /// Complete season projection.
  final List<CharacterView> cachedRows;
  final bool isStale;
  final List<CharacterOverlay> overlays;

  /// Last command failure keyed by its stable problem `code`.
  final ProblemError? commandError;

  /// The `*.not-found` problem of a deleted parent (D5).
  ProblemError? get notFound {
    final p = projected;
    if (p is AsyncError) {
      final error = p.error;
      if (error is ProblemError && error.code.endsWith('.not-found')) {
        return error;
      }
    }
    return null;
  }

  /// The merged list the screen renders: authoritative rows plus optimistic
  /// overlays by `id`.
  List<CharacterRow> get rows {
    final projectedIds = {for (final c in cachedRows) c.id};
    return <CharacterRow>[
      for (final c in cachedRows) ProjectedCharacterRow(c),
      for (final o in overlays)
        if (!projectedIds.contains(o.id)) OptimisticCharacterRow(o),
    ];
  }

  /// Name lookup for the costume assign picker + scene binding (read-DTO
  /// join — never aggregate reconstruction).
  Map<String, String> get namesById => {
    for (final c in cachedRows) c.id: c.name,
  };
}

/// Category chip label for the exhaustive `main_cast|guest|extra`
/// discriminator (unknown variants never reach the UI — the DTO strictly
/// rejects them at parse time).
String characterCategoryLabel(CharacterView character) {
  final wire = serializers.serializeWith(
    CharacterCategory.serializer,
    character.category,
  );
  return switch (wire) {
    'main_cast' => 'Main cast',
    'guest' => 'Guest',
    'extra' => 'Extra',
    _ => 'Unknown',
  };
}
