## MODIFIED Requirements

### Requirement: One projector per aggregate, each with its own checkpoint
`crates/infra` SHALL provide four `EntityEventHandler<sqlx::Transaction<'static, Postgres>` impls — `SceneProjector`, `CharacterProjector`, `CostumeProjector`, `CalculationProjector` — each spawned as its own `kameo_es` `PostgresProcessor` actor with an independent `sierradb_event_checkpoints` row set per partition. A single composite handler SHALL NOT be used. Each projector's SierraDB subscription stream SHALL be supervised by an in-process supervisor that restarts the stream on error or panic from its checkpoint with bounded backoff, so that a per-task failure does not silently stall the projection until the whole API process is restarted.

#### Scenario: Independent failure isolation
- **WHEN** `CharacterProjector` raises an error handling one event
- **THEN** `SceneProjector`, `CostumeProjector` and `CalculationProjector` continue processing their own event streams unaffected

#### Scenario: Independent catch-up
- **WHEN** `CostumeProjector` is restarted after a downtime
- **THEN** it replays from its own checkpoint without resetting the checkpoints of the other three projectors

#### Scenario: Per-task failure restarts within the process
- **WHEN** one projector's subscription stream task returns an error or panics while the API process keeps running
- **THEN** the supervisor for that projector restarts its subscription loop from its checkpoint without restarting the API process
- **AND** the other three projectors' subscription loops are not affected by that single task's failure
