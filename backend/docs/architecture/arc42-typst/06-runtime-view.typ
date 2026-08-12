// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: kimi-k3 (neuralwatt)

#import "template.typ": *


= Runtime View

== Scenario: Create Scene (with AuthZ)

#diagram("create-scene-sequence", caption: [Authenticated create command with injected season scope])

*Observed properties*:

- AuthZ is an explicit handler-internal gate (`AUTHZ-GATE`); season
  membership checked before any aggregate access.
- Validation failures are `DomainError` replies, turned into RFC 9457
  `problem+json` by the handler.
- Event appending to SierraDB is idempotent per stream and version;
  projectors run asynchronously.

== Scenario: Query Scenes

#diagram("query-scenes-sequence", caption: [Read path — CQRS aware])

*Observed properties*:

- No event store or aggregate on the path — projections are the only read model.
- Filtering and ordering use the projection's own sort keys (e.g.
  `lexical_sort_key`).

== Scenario: Photo Upload with Thumbnail Saga

#diagram("photo-upload-saga-sequence", caption: [Photo upload lifecycle])

*Observed properties*:

- Upload acknowledged immediately (202), work happens asynchronously.
- The thumbnail saga decodes, strips EXIF, generates Thumb/Medium variants,
  and appends the follow-up command.

== Scenario: Photo Deletion with Refcount

A `PhotoUnlinked` event decrements the reference count via
`projection_costume_photo`; when it reaches zero, a deletion saga dispatches
`DeletePhoto`. AI payload GC works the same way: cleanup marks are written
only after real deletions (issue #206).

== Scenario: AI Script Import (Job Queue)

The worker claims a job with a lease and fencing; renews at ~1/3 lease
window; writes source/preview payloads to Garage; never marks a job
`failed` for `payload_unavailable`; never sweeps `failed` rows.

// TODO: add panic/error handling scenario (retry_transient, lease fencing)
