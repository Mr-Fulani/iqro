# ADR: Independent audio roles and playback channels

Status: accepted

Date: 2026-09-21

## Decision

An audio choice is a concrete `RecitationEdition`/audio variant ID. The
person-level `Reciter` profile is not a selectable playback identity by itself.
The backend advertises additive capabilities for `listen`, `ayah_playback`,
`memorization`, and `offline`, plus coverage counts. A variant without verified
ayah timings can be used for ordinary listening only.

The Flutter client keeps three independent preferences:

- Listening: the global Audio tab and mini-player;
- Mushaf: contextual ayah playback;
- Memorization: the default for new plans, while an existing plan stores its
  exact variant ID as the source of truth.

The shared physical engine has logical ownership channels: `listening`,
`mushaf`, and `memorization`. Shared engine mechanics remain in one controller,
but only Listening writes the playback snapshot/remote position and exposes the
global mini-player. Contextual channels may interrupt the physical engine; when
Memorization is left, its channel is stopped and the paused Listening snapshot
is restored.

## Compatibility

The old `reader_recitation_id` key remains readable and is used as the fallback
for all roles on first migration. New writes use role-specific keys and keep the
legacy Listening key for older clients. Backend fields are additive; existing
audio endpoints and default asset fields remain unchanged.

## Consequences

- Untimed provider assets do not leak into Mushaf or Memorization selection.
- A Memorization choice cannot change the Audio tab's selected variant.
- The engine is not duplicated per feature, reducing interruption and resource
  handling drift on Android and iOS.
- A future ayah-by-ayah provider can implement the same role contract through a
  typed resolver without creating a provider-specific UI path.
